import AppKit
import Combine
import AVFoundation
import CoreGraphics
import RestFlowCore
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !restoringSettings else { return }
            accountElapsed(schedule: oldValue.operatingSchedule)
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
                    // @Published's setter re-enters didSet; restoring must not retry a failed save/integration.
                    restoringSettings = true
                    settings = oldValue
                    restoringSettings = false
                    configurationError = error.localizedDescription
                }
            }
            engine.plan = settings.plan
            synchronizeOperatingHours()
            flushStatistics()
            if settings.mediaPath != oldValue.mediaPath || settings.language != oldValue.language { validateMedia() }
            if settings.soundPath != oldValue.soundPath || settings.soundName != oldValue.soundName || settings.language != oldValue.language {
                validateSound()
            }
            if settings.messages != oldValue.messages || settings.shortMessageID != oldValue.shortMessageID ||
                settings.longMessageID != oldValue.longMessageID || settings.visualID != oldValue.visualID ||
                settings.excludedVisualIDs != oldValue.excludedVisualIDs {
                prepareBreakContent()
            }
            if settings.soundName != oldValue.soundName || settings.soundPath != oldValue.soundPath || settings.excludedSoundIDs != oldValue.excludedSoundIDs {
                feedback.stop()
            }
            if settings.language != oldValue.language { feedback.registerActions(language: settings.language) }
            publish(at: now)
            onSettingsChange?()
        }
    }
    @Published private(set) var isPreview = false
    @Published private(set) var isAway = false
    @Published private(set) var canDefer = false
    private var previewSnapshot: (engine: SessionEngine, running: Bool, resumeAfterSleep: Bool)?
    private var lastShownMessageID: String?
    private var lastShownVisual: BuiltinVisual?
    private var focusToken = UUID().uuidString
    private var awayResetAt: TimeInterval?
    private var idlePauseAt: TimeInterval?
    private var screenLocked = false
    private var lockObservers: [NSObjectProtocol] = []
    private let idleSeconds: () -> TimeInterval
    @Published private(set) var isOutsideOperatingHours = false
    @Published private(set) var statisticsDays: [DailyStatistics] = []
    @Published private(set) var statisticsError: String?
    let statistics: StatisticsStore
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
    @Published private(set) var focusNoiseError: String?
    private(set) var resolvedNoiseIDs: [String] = []
    private(set) var randomNoiseID: String?
    private var previousRandomNoiseID: String?
    private var noiseFocusToken: String?
    private var noiseRandomWasEnabled = false
    let focusNoise: FocusNoisePlayer
    @Published private(set) var mediaIsValid = true
    let shortcuts = ShortcutController()
    let loginItem: any LoginItemManaging
    let feedback = FeedbackService()
    let configuration: ConfigurationStore
    var onPhaseChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var onRefresh: (() -> Void)?
    private var engine: SessionEngine
    private var timer: Timer?
    private var applyingFile = false
    private var restoringSettings = false
    private var nextConfigCheck: TimeInterval = 0
    private var resumeAfterSleep = false
    private var workspaceObservers: [NSObjectProtocol] = []

    private var schedulePaused = false
    private var scheduleBoundary: TimeInterval?
    private var lastObservation: (time: TimeInterval, date: Date)?
    private var observedRest = false
    private var lastRestDate = Date()
    private var nextStatisticsSave: TimeInterval = 0
    private let wallClock: () -> Date
    private let clock: () -> TimeInterval
    private var now: TimeInterval { clock() }

    init(directory: URL? = nil, loginItem: (any LoginItemManaging)? = nil, focusNoise: FocusNoisePlayer? = nil,
         idleSeconds: (() -> TimeInterval)? = nil,
         wallClock: @escaping () -> Date = Date.init,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.focusNoise = focusNoise ?? FocusNoisePlayer()
        self.clock = clock
        self.idleSeconds = idleSeconds ?? (directory == nil ? {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        } : { 0 })
        self.wallClock = wallClock
        self.loginItem = loginItem ?? LoginItemController()
        let configuration = ConfigurationStore(directory: directory ?? ConfigurationStore.defaultDirectory)
        self.configuration = configuration
        statistics = StatisticsStore(directory: configuration.directory)
        do { try statistics.load() } catch { statisticsError = error.localizedDescription }
        statisticsDays = statistics.days.values.sorted { $0.id < $1.id }
        MediaStore.configurationDirectory = configuration.directory
        let loaded: AppSettings
        var errorMessage: String?
        do { loaded = try configuration.load(orCreate: directory == nil ? SettingsMigration.legacySettings() : AppSettings()) }
        catch {
            loaded = AppSettings()
            errorMessage = error.localizedDescription
        }
        settings = loaded
        let initialContent = BreakContent(settings: loaded)
        breakContent = initialContent
        engine = SessionEngine(plan: loaded.plan, now: clock())
        phase = engine.phase
        remaining = loaded.plan.workDuration
        configurationError = errorMessage
        do {
            try shortcuts.apply(loaded)
            if directory == nil && loaded.launchAtLogin { try self.loginItem.apply(enabled: true) }
        } catch { configurationError = error.localizedDescription }
        if errorMessage != nil {
            engine.pause(at: clock())
            isPaused = true
        }
        lastObservation = (clock(), wallClock())
        synchronizeOperatingHours()
        publish(at: clock())
    }

    func prepareBreakContent() {
        breakContent = BreakContent(settings: settings, avoidingMessageID: lastShownMessageID, avoidingVisual: lastShownVisual)
        lastShownMessageID = engine.phase == .longBreak ? breakContent.longMessageID : breakContent.shortMessageID
        lastShownVisual = breakContent.visual
    }

    func previewBreak() {
        guard !engine.phase.isBreak else { return }
        refresh()
        guard !engine.phase.isBreak else { return }
        let running = !engine.isPaused
        var saved = engine
        saved.pause(at: now)
        previewSnapshot = (saved, running, resumeAfterSleep)
        isPreview = true
        engine.startShortBreak(at: now)
        prepareBreakContent()
        feedback.stop(); feedback.clearNotification()
        publish(at: now)
        onPhaseChange?()
    }

    private func finishPreview() {
        guard let saved = previewSnapshot else { return }
        engine = saved.engine
        resumeAfterSleep = saved.resumeAfterSleep
        engine.plan = settings.plan
        if saved.running { engine.resume(at: now) }
        previewSnapshot = nil
        isPreview = false
        lastObservation = (now, wallClock())
        synchronizeOperatingHours()
        publish(at: now)
        onPhaseChange?()
    }

    func deferBreak(token: String? = nil) {
        if let token, token != focusToken { return }
        refresh()
        guard canDefer, engine.deferBreak(at: now) else { return }
        feedback.stop(); feedback.clearNotification()
        publish(at: now)
    }


    func selectVisual(_ id: String) {
        var updated = settings
        updated.visualID = id
        updated.mediaPath = nil
        let previous = settings.mediaPath
        settings = updated
        if settings.mediaPath == nil { MediaStore.removeManaged(path: previous) }
    }

    func selectSound(_ id: String) {
        var updated = settings
        if id == "__custom__" {
            guard updated.soundPath != nil else { return }
        } else {
            updated.soundName = id
            updated.soundPath = nil
        }
        updated.soundEnabled = id != AppSettings.noSoundID
        settings = updated
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
    func toggleFocusNoise() { settings.toggleFocusNoise() }

    func hideSelectedSound() {
        var updated = settings
        if updated.soundPath != nil {
            updated.soundPath = nil; updated.soundName = AppSettings.noSoundID
        } else { guard updated.hideSound(updated.soundName) else { return } }
        settings = updated
        feedback.stop()
    }

    var menuStatusText: String {
        if isPreview { return text("预览：", "Preview: ") + timeText }
        if isAway { return text("已离开 · 计时暂停", "Away · Timer paused") }
        if isOutsideOperatingHours { return text("非运行时段", "Outside operating hours") }
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
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setScreenLocked(locked) }
            })
        }
        feedback.registerActions(language: settings.language)
        refreshNotificationStatus()
        validateMedia()
        validateSound()
        refresh()
    }

    func stop() {
        if isPreview { finishPreview() }
        accountElapsed()
        synchronizeOperatingHours()
        finishObservedBreak(completed: engine.remaining(at: now) <= 0)
        flushStatistics()
        timer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lockObservers.removeAll()
        feedback.stop()
        focusNoise.stop()
        feedback.clearNotification()
        shortcuts.stop()
    }

    func refresh() {
        var current = now
        if current >= nextConfigCheck {
            nextConfigCheck = current + 1
            reloadConfiguration()
        }
        accountElapsed()
        synchronizePresence()
        synchronizeOperatingHours()
        current = now
        let wasBreak = engine.phase.isBreak
        let events = engine.tick(at: current)
        if wasBreak && engine.phase == .work && isPreview { finishPreview(); return }
        if wasBreak && engine.phase == .work { finishObservedBreak(completed: true); focusToken = UUID().uuidString }
        if current >= nextStatisticsSave { flushStatistics(); nextStatisticsSave = current + 15 }
        if !wasBreak && engine.phase.isBreak { prepareBreakContent() }
        publish(at: current)
        for event in events {
            switch event {
            case .warning:
                let nextBreak: SessionPhase = completedWorkSessions + 1 >= settings.cycles ? .longBreak : .shortBreak
                guard settings.shouldPrealert(for: nextBreak) else { continue }
                feedback.notifyBreak(in: Int(ceil(remaining)), language: settings.language, deferToken: canDefer ? focusToken : nil)
                playSound()
            case .phaseChanged:
                if phase.isBreak { beginObservedBreak() }
                feedback.clearNotification()
                playSound()
                onPhaseChange?()
            }
        }
    }

    func togglePause() {
        guard isPreview || (!isOutsideOperatingHours && !isAway) else { return }
        resumeAfterSleep = false
        refresh()
        guard isPreview || (!isOutsideOperatingHours && !isAway) else { return }
        let current = now
        if engine.isPaused { engine.resume(at: current) } else { engine.pause(at: current) }
        feedback.clearNotification()
        publish(at: current)
        flushStatistics()
    }

    func restart() {
        if isPreview { finishPreview() }
        focusToken = UUID().uuidString
        resumeAfterSleep = false
        accountElapsed()
        synchronizeOperatingHours()
        finishObservedBreak(completed: engine.remaining(at: now) <= 0)
        schedulePaused = false
        engine.restart(at: now)
        synchronizeOperatingHours()
        flushStatistics()
        feedback.stop()
        feedback.clearNotification()
        publish(at: now)
        onPhaseChange?()
    }

    func startShortBreak() {
        guard !phase.isBreak, !isOutsideOperatingHours else { return }
        accountElapsed()
        resumeAfterSleep = false
        synchronizeOperatingHours()
        guard !isOutsideOperatingHours else { return }
        engine.startShortBreak(at: now)
        beginObservedBreak()
        prepareBreakContent()
        feedback.clearNotification()
        playSound()
        publish(at: now)
        onPhaseChange?()
    }

    func restNow() {
        refresh()
        guard !engine.phase.isBreak, !isOutsideOperatingHours, !isAway else { return }
        accountElapsed()
        resumeAfterSleep = false
        engine.restNow(at: now)
        beginObservedBreak()
        prepareBreakContent()
        feedback.clearNotification()
        playSound()
        publish(at: now)
        flushStatistics()
        onPhaseChange?()
    }

    func endBreak() {
        guard engine.phase.isBreak else { return }
        if isPreview { finishPreview(); return }
        focusToken = UUID().uuidString
        resumeAfterSleep = false
        accountElapsed()
        synchronizeOperatingHours()
        guard engine.phase.isBreak else { flushStatistics(); return }
        finishObservedBreak(completed: engine.remaining(at: now) <= 0)
        engine.endBreak(at: now)
        synchronizeOperatingHours()
        flushStatistics()
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

    func deleteMessage(_ id: String) {
        var updated = settings
        guard updated.deleteMessage(id) else { return }
        settings = updated
    }

    func deleteSelectedVisual() {
        var updated = settings
        let path = updated.mediaPath
        if path != nil {
            updated.mediaPath = nil
            updated.visualID = BuiltinVisual.noneID
        } else if !updated.deleteVisual(updated.visualID) { return }
        settings = updated
        if settings.mediaPath == nil { MediaStore.removeManaged(path: path) }
    }

    func importSound() {
        let panel = NSOpenPanel()
        panel.title = text("选择提示音", "Choose a sound")
        panel.allowedContentTypes = [.wav, .aiff, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do { try importAudio(from: source) }
        catch { configurationError = error.localizedDescription }
    }

    func importAudio(from source: URL) throws {
        guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20 * 1024 * 1024,
              (try? AVAudioPlayer(contentsOf: source)) != nil else {
            throw ConfigurationError.invalid(text("声音无效或超过 20 MB。", "The sound is invalid or larger than 20 MB."))
        }
        let folder = configuration.directory.appendingPathComponent("sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).\(source.pathExtension)"
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        var updated = settings
        updated.soundPath = "sounds/\(name)"; updated.soundEnabled = true
        settings = updated
        if settings.soundPath != "sounds/\(name)" {
            try? FileManager.default.removeItem(at: destination)
            throw ConfigurationError.invalid(configurationError ?? text("声音未保存。", "Sound was not saved."))
        }
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
        } else { valid = settings.soundName == AppSettings.randomSoundID || FeedbackService.alertSound(settings.soundName) != nil }
        soundError = valid ? nil : text("声音无法读取，请检查 soundPath 或 soundName。", "Unable to read sound. Check soundPath or soundName.")
    }

    private func publish(at current: TimeInterval) {
        canDefer = settings.deferEnabled && !isPreview && !isAway && !isOutsideOperatingHours &&
            engine.phase == .work && !engine.isPaused && !engine.didDefer && engine.remaining(at: current) > 0
        phase = engine.phase
        isPaused = engine.isPaused
        remaining = engine.remaining(at: current)
        completedWorkSessions = engine.completedWorkSessions
        progress = max(0, min(1, 1 - remaining / engine.phaseDuration))
        synchronizeFocusNoise()
        onRefresh?()
    }

    private func synchronizeFocusNoise() {
        // Preview temporarily borrows the timer; keep the original focus's selection and playhead.
        let newSegment = noiseFocusToken != focusToken
        let invalidRandom = randomNoiseID.map { settings.focusNoiseIDs.contains($0) } ?? true
        if newSegment || settings.focusNoiseRandom != noiseRandomWasEnabled || (settings.focusNoiseRandom && invalidRandom) {
            randomNoiseID = settings.randomFocusNoise(avoiding: previousRandomNoiseID)
            if let randomNoiseID { previousRandomNoiseID = randomNoiseID }
            noiseFocusToken = focusToken
            noiseRandomWasEnabled = settings.focusNoiseRandom
        }
        resolvedNoiseIDs = settings.focusNoiseIDs + (randomNoiseID.map { [$0] } ?? [])
        let retainMix = settings.focusNoiseEnabled && (phase == .work || isPreview)
        let running = retainMix && !isPreview && !isPaused && !isAway && !isOutsideOperatingHours && !screenLocked
        let error = focusNoise.sync(ids: retainMix ? resolvedNoiseIDs : [], volume: settings.focusNoiseVolume, running: running)
        let message = error.map { text("白噪音无法播放：", "Unable to play focus noise: ") + $0 }
        if focusNoiseError != message { focusNoiseError = message }
    }

    func willSleep() {
        accountElapsed()
        flushStatistics()
        guard !engine.isPaused else { return }
        engine.pause(at: now)
        resumeAfterSleep = true
        feedback.stop()
        feedback.clearNotification()
        publish(at: now)
    }

    func didWake() {
        lastObservation = (now, wallClock())
        guard resumeAfterSleep else { return }
        resumeAfterSleep = false
        engine.resume(at: now)
        refresh()
    }

    private func accountElapsed(schedule: OperatingSchedule? = nil) {
        let current = now, date = wallClock()
        defer { lastObservation = (current, date) }
        guard let previous = lastObservation, !isPreview else { return }
        let elapsed = current - previous.time
        // A clock/timezone correction cannot invent hours of activity.
        guard elapsed > 0, abs(date.timeIntervalSince(previous.date) - elapsed) < 2 else { return }
        if isAway {
            statistics.recordAway(from: previous.date, to: date, schedule: schedule ?? settings.operatingSchedule)
            statisticsDays = statistics.days.values.sorted { $0.id < $1.id }
            return
        }
        guard !engine.isPaused else { return }
        var duration = min(elapsed, engine.remaining(at: previous.time))
        if settings.idleDetectionEnabled, engine.phase == .work {
            let boundary = current - max(0, idleSeconds() - 60)
            if idleSeconds() >= 60 {
                idlePauseAt = max(previous.time, boundary)
                duration = min(duration, max(0, boundary - previous.time))
                let awayStart = previous.date.addingTimeInterval(max(0, boundary - previous.time))
                statistics.recordAway(from: awayStart, to: date, schedule: schedule ?? settings.operatingSchedule)
            }
        }
        let schedule = schedule ?? settings.operatingSchedule
        if schedule.enabled, let window = schedule.windows(on: previous.date).first(where: { previous.date >= $0.start && previous.date < $0.end }), date >= window.end {
            let untilEnd = window.end.timeIntervalSince(previous.date)
            duration = min(duration, untilEnd)
            scheduleBoundary = previous.time + untilEnd
        }
        guard duration > 0 else { return }
        let end = previous.date.addingTimeInterval(duration)
        let recorded = statistics.record(from: previous.date, to: end, phase: engine.phase, schedule: schedule)
        if engine.phase.isBreak, recorded > 0 {
            observedRest = true
            lastRestDate = (schedule.segments(from: previous.date, to: end).last?.end ?? end).addingTimeInterval(-0.001)
        }
        let days = statistics.days.values.sorted { $0.id < $1.id }
        if days != statisticsDays { statisticsDays = days }
    }

    private func beginObservedBreak() {
        observedRest = true
        lastRestDate = wallClock()
    }

    private func finishObservedBreak(completed: Bool) {
        guard observedRest else { return }
        statistics.finishBreak(on: lastRestDate, completed: completed)
        observedRest = false
        statisticsDays = statistics.days.values.sorted { $0.id < $1.id }
    }

    private func flushStatistics() {
        do { try statistics.save(); statisticsError = nil }
        catch { statisticsError = error.localizedDescription }
    }

    /// Only elapsed idle duration is observed; no input contents or application names are collected.
    private func synchronizePresence() {
        guard !isPreview else { return }
        let idle = max(0, idleSeconds())
        let absent = screenLocked || (settings.idleDetectionEnabled && idle >= 60)
        if isAway && !absent {
            let longAbsence = now >= (awayResetAt ?? .infinity)
            isAway = false; awayResetAt = nil
            if longAbsence { engine.resumeAfterAbsence(at: now); focusToken = UUID().uuidString }
            else { engine.resume(at: now) }
            synchronizeOperatingHours()
            publish(at: now)
            onPhaseChange?()
        } else if !isAway && absent && !engine.isPaused && engine.phase == .work {
            engine.pause(at: idlePauseAt ?? now)
            idlePauseAt = nil
            awayResetAt = now + (screenLocked ? 300 : max(0, 300 - idle))
            isAway = true
            feedback.stop(); feedback.clearNotification()
            publish(at: now)
        }
    }

    func setScreenLocked(_ locked: Bool) {
        guard !isPreview else { if locked { finishPreview(); setScreenLocked(true) }; return }
        accountElapsed()
        if locked && resumeAfterSleep {
            // Transfer the sleep pause to the lock owner; wake must not release it.
            resumeAfterSleep = false
            engine.resume(at: now)
        }
        screenLocked = locked
        if locked && engine.phase.isBreak {
            let manuallyPaused = engine.isPaused && !resumeAfterSleep
            finishObservedBreak(completed: engine.remaining(at: now) <= 0)
            engine.endBreak(at: now)
            if manuallyPaused { engine.pause(at: now) }
            focusToken = UUID().uuidString
            publish(at: now)
            onPhaseChange?()
        }
        synchronizePresence()
        synchronizeOperatingHours()
        publish(at: now)
        flushStatistics()
    }

    private func synchronizeOperatingHours() {
        guard !isPreview else { return }
        let previousPhase = engine.phase, previouslyPaused = engine.isPaused
        let outside = !settings.operatingSchedule.contains(wallClock())
        if let boundary = scheduleBoundary {
            if engine.phase.isBreak {
                finishObservedBreak(completed: engine.remaining(at: boundary) <= 0)
                engine.endBreak(at: boundary)
                focusToken = UUID().uuidString
            }
            if !engine.isPaused { engine.pause(at: boundary); schedulePaused = true }
            scheduleBoundary = nil
        }
        let changed = outside != isOutsideOperatingHours
        isOutsideOperatingHours = outside
        if outside {
            if engine.phase.isBreak {
                finishObservedBreak(completed: false)
                engine.endBreak(at: now)
                focusToken = UUID().uuidString
            }
            if !engine.isPaused {
                engine.pause(at: now)
                schedulePaused = true
            }
            feedback.stop()
            feedback.clearNotification()
        } else if schedulePaused && !isAway {
            engine.resume(at: now)
            schedulePaused = false
        }
        if changed || previousPhase != engine.phase || previouslyPaused != engine.isPaused { publish(at: now) }
        if changed || previousPhase != engine.phase { onPhaseChange?() }
    }

    var timeText: String { Self.formatTime(remaining) }
    static func formatTime(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
