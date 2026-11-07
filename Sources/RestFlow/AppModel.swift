import AppKit
import Combine
import RestFlowCore
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if !applyingFile {
                let loginChanged = settings.launchAtLogin != oldValue.launchAtLogin
                let loginWasEnabled = loginChanged && (loginItem.status == .enabled || loginItem.status == .requiresApproval)
                var changedLoginItem = false
                do {
                    try shortcuts.apply(settings)
                    if loginChanged {
                        try loginItem.apply(enabled: settings.launchAtLogin)
                        changedLoginItem = true
                    }
                    try configuration.save(settings)
                    configurationError = nil
                } catch {
                    try? shortcuts.apply(oldValue)
                    if changedLoginItem { try? loginItem.apply(enabled: loginWasEnabled) }
                    settings = oldValue
                    configurationError = error.localizedDescription
                }
            }
            engine.plan = settings.plan
            if settings.mediaPath != oldValue.mediaPath || settings.language != oldValue.language { validateMedia() }
            if settings.soundPath != oldValue.soundPath || settings.soundName != oldValue.soundName || settings.language != oldValue.language {
                validateSound()
            }
            if settings.messages != oldValue.messages || settings.shortMessageID != oldValue.shortMessageID ||
                settings.longMessageID != oldValue.longMessageID || settings.visualID != oldValue.visualID {
                prepareBreakContent()
            }
            onSettingsChange?()
            onRefresh?()
        }
    }
    @Published private(set) var breakContent = BreakContent(settings: AppSettings())
    @Published private(set) var phase: SessionPhase
    @Published private(set) var isPaused = false
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var progress: Double = 0
    @Published private(set) var completedWorkSessions = 0
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @Published var configurationError: String?
    @Published var mediaError: String?
    @Published var soundError: String?
    @Published private(set) var mediaIsValid = true
    let shortcuts = ShortcutController()
    let loginItem = LoginItemController()
    let feedback = FeedbackService()
    let configuration: ConfigurationStore
    var onPhaseChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var onRefresh: (() -> Void)?
    private var engine: SessionEngine
    private var timer: Timer?
    private var applyingFile = false
    private var nextConfigCheck: TimeInterval = 0
    private var resumeAfterSleep = false
    private var workspaceObservers: [NSObjectProtocol] = []

    private let clock: () -> TimeInterval
    private var now: TimeInterval { clock() }

    init(directory: URL? = nil, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        let configuration = ConfigurationStore(directory: directory ?? ConfigurationStore.defaultDirectory)
        self.configuration = configuration
        MediaStore.configurationDirectory = configuration.directory
        let loaded: AppSettings
        var errorMessage: String?
        do { loaded = try configuration.load(orCreate: directory == nil ? SettingsMigration.legacySettings() : AppSettings()) }
        catch {
            loaded = AppSettings()
            errorMessage = error.localizedDescription
        }
        settings = loaded
        breakContent = BreakContent(settings: loaded)
        engine = SessionEngine(plan: loaded.plan, now: clock())
        phase = engine.phase
        remaining = loaded.plan.workDuration
        configurationError = errorMessage
        do {
            try shortcuts.apply(loaded)
            if directory == nil && loaded.launchAtLogin { try loginItem.apply(enabled: true) }
        } catch { configurationError = error.localizedDescription }
        if errorMessage != nil {
            engine.pause(at: clock())
            isPaused = true
        }
    }

    func prepareBreakContent() { breakContent = BreakContent(settings: settings) }

    func selectVisual(_ id: String) {
        var updated = settings
        updated.visualID = id
        updated.mediaPath = nil
        let previous = settings.mediaPath
        settings = updated
        if settings.mediaPath == nil { MediaStore.removeManaged(path: previous) }
    }

    func text(_ chinese: String, _ english: String) -> String { settings.language.text(chinese, english) }
    var phaseTitle: String {
        switch phase {
        case .work: return text("专注", "Focus")
        case .shortBreak: return text("短休息", "Short break")
        case .longBreak: return text("长休息", "Long break")
        }
    }
    var mediaURL: URL? { configuration.resolve(settings.mediaPath) }
    var soundURL: URL? { configuration.resolve(settings.soundPath) }
    var menuStatusText: String {
        let phase = phase.isBreak ? text("休息", "Rest") : text("专注", "Focus")
        return phase + text("：", ": ") + timeText + (isPaused ? text(" · 已暂停", " · Paused") : "")
    }

    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.willSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        })
        refreshNotificationStatus()
        validateMedia()
        validateSound()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        feedback.stop()
        feedback.clearNotification()
        shortcuts.stop()
    }

    func refresh() {
        let current = now
        if current >= nextConfigCheck {
            nextConfigCheck = current + 1
            reloadConfiguration()
        }
        let events = engine.tick(at: current)
        publish(at: current)
        for event in events {
            switch event {
            case .warning:
                let nextBreak: SessionPhase = completedWorkSessions + 1 >= settings.cycles ? .longBreak : .shortBreak
                guard settings.shouldPrealert(for: nextBreak) else { continue }
                feedback.notifyBreak(in: Int(ceil(remaining)), language: settings.language)
                playSound()
            case .phaseChanged:
                if phase.isBreak { prepareBreakContent() }
                feedback.clearNotification()
                playSound()
                onPhaseChange?()
            }
        }
    }

    func togglePause() {
        resumeAfterSleep = false
        refresh()
        let current = now
        if engine.isPaused { engine.resume(at: current) } else { engine.pause(at: current) }
        feedback.clearNotification()
        publish(at: current)
    }

    func restart() {
        resumeAfterSleep = false
        engine.restart(at: now)
        feedback.stop()
        feedback.clearNotification()
        publish(at: now)
        onPhaseChange?()
    }

    func startShortBreak() {
        guard !phase.isBreak else { return }
        resumeAfterSleep = false
        engine.startShortBreak(at: now)
        prepareBreakContent()
        feedback.clearNotification()
        playSound()
        publish(at: now)
        onPhaseChange?()
    }

    func endBreak() {
        guard engine.phase.isBreak else { return }
        resumeAfterSleep = false
        engine.endBreak(at: now)
        playSound()
        feedback.clearNotification()
        publish(at: now)
        onPhaseChange?()
    }

    func reloadConfiguration(force: Bool = false) {
        do {
            guard let loaded = try configuration.reload(force: force, validate: { loaded in
                try shortcuts.apply(loaded)
                if loaded.launchAtLogin != settings.launchAtLogin {
                    do { try loginItem.apply(enabled: loaded.launchAtLogin) }
                    catch { try? shortcuts.apply(settings); throw error }
                }
            }) else { return }
            applyingFile = true
            settings = loaded
            applyingFile = false
            configurationError = nil
        } catch { configurationError = error.localizedDescription }
    }

    func openConfiguration() { NSWorkspace.shared.open(configuration.fileURL) }
    func revealConfiguration() { NSWorkspace.shared.activateFileViewerSelecting([configuration.fileURL]) }

    func importMedia() {
        do {
            guard let media = try MediaStore.chooseAndImport(language: settings.language) else { return }
            let previous = settings.mediaPath
            settings.mediaPath = "media/\(media.folder)/\(media.fileName)"
            if settings.mediaPath != previous { MediaStore.removeManaged(path: previous) }
        } catch { mediaError = error.localizedDescription }
    }

    func removeMedia() {
        let previous = settings.mediaPath
        settings.mediaPath = nil
        if settings.mediaPath == nil { MediaStore.removeManaged(path: previous) }
    }

    func importSound() {
        let panel = NSOpenPanel()
        panel.title = text("选择提示音", "Choose a sound")
        panel.allowedContentTypes = [.wav, .aiff, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20 * 1024 * 1024,
                  NSSound(contentsOf: source, byReference: false) != nil else {
                throw ConfigurationError.invalid(text("声音无效或超过 20 MB。", "The sound is invalid or larger than 20 MB."))
            }
            let folder = configuration.directory.appendingPathComponent("sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).\(source.pathExtension)"
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
            settings.soundPath = "sounds/\(name)"
        } catch { configurationError = error.localizedDescription }
    }

    func playSound() { feedback.play(settings: settings, customURL: soundURL) }

    enum MessageAdditionResult { case added, duplicate, invalid, failed }

    func addMessage(_ text: String) -> MessageAdditionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= 2000 else { return .invalid }
        guard !settings.containsMessage(text) else { return .duplicate }
        guard settings.messages.count < 100 else { return .invalid }
        let message = ReminderMessage(text: text)
        settings.messages.append(message)
        return settings.messages.contains(where: { $0.id == message.id }) ? .added : .failed
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.configurationError = error.localizedDescription }
                else { self?.refreshNotificationStatus() }
            }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notification in
            Task { @MainActor in self?.notificationAuthorization = notification.authorizationStatus }
        }
    }

    var notificationStatus: String {
        switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return text("已允许通知", "Notifications allowed")
        case .denied: return text("已关闭；可在系统设置 → 通知中开启", "Disabled. Enable in System Settings → Notifications.")
        case .notDetermined: return text("尚未授权", "Permission not requested")
        @unknown default: return text("未知通知状态", "Unknown notification status")
        }
    }

    private func validateMedia() {
        guard let url = mediaURL else { mediaError = nil; mediaIsValid = true; return }
        do { try MediaStore.validate(url, language: settings.language); mediaError = nil; mediaIsValid = true }
        catch { mediaError = error.localizedDescription; mediaIsValid = false }
    }

    private func validateSound() {
        guard settings.soundPath != nil || settings.soundName != AppSettings.noSoundID else {
            soundError = nil
            return
        }
        let valid: Bool
        if let url = soundURL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
            valid = size <= 20 * 1024 * 1024 && NSSound(contentsOf: url, byReference: false) != nil
        } else { valid = NSSound(named: NSSound.Name(settings.soundName)) != nil }
        soundError = valid ? nil : text("声音无法读取，请检查 soundPath 或 soundName。", "Unable to read sound. Check soundPath or soundName.")
    }

    private func publish(at current: TimeInterval) {
        phase = engine.phase
        isPaused = engine.isPaused
        remaining = engine.remaining(at: current)
        completedWorkSessions = engine.completedWorkSessions
        progress = max(0, min(1, 1 - remaining / engine.phaseDuration))
        onRefresh?()
    }

    private func willSleep() {
        guard !engine.isPaused else { return }
        engine.pause(at: now)
        resumeAfterSleep = true
        feedback.stop()
        feedback.clearNotification()
        publish(at: now)
    }

    private func didWake() {
        guard resumeAfterSleep else { return }
        resumeAfterSleep = false
        engine.resume(at: now)
        refresh()
    }

    var timeText: String { Self.formatTime(remaining) }
    static func formatTime(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
