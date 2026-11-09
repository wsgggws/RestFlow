import AppKit
import SwiftUI
import UserNotifications
import RestFlowCore
import ServiceManagement

@main
enum RestFlowApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--check-activity-integration") { exit(ActivityIntegrationChecks.run()) }
        if CommandLine.arguments.contains("--check-name-integration") {
            exit(AppIdentity.checkIntegration())
        }
        if CommandLine.arguments.contains("--check-system-integration") {
            exit(SystemIntegrationChecks.run())
        }
        if CommandLine.arguments.contains("--check-break-integration") {
            app.setActivationPolicy(.accessory)
            exit(BreakIntegrationChecks.run())
        }
        if CommandLine.arguments.contains("--check-menu-integration") {
            app.setActivationPolicy(.accessory)
            exit(AppDelegate.checkMenuIntegration())
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel!
    private let updates = UpdateChecker()
    private var lastShowsTime: Bool?
    private var lastStatusTitle: String?
    private var breakWindows: BreakWindowController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var phaseMenuItem: NSMenuItem?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let configDirectory = args.firstIndex(of: "--config-dir").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1], isDirectory: true) : nil }
        model = AppModel(directory: configDirectory)
        breakWindows = BreakWindowController(model: model)
        model.shortcuts.perform = { [weak self] action in
            switch action {
            case .pause: self?.togglePause()
            case .restart: self?.restart()
            case .restNow: self?.restNow()
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: AppIdentity.displayName)!
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel(AppIdentity.displayName)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        model.onRefresh = { [weak self] in self?.refreshStatus() }
        model.onPhaseChange = { [weak self] in self?.breakWindows.sync() }
        model.onSettingsChange = { [weak self] in
            guard let self else { return }
            self.settingsWindow?.title = self.settingsTitle
            self.breakWindows.updateTitles()
            self.breakWindows.reconcilePresentation()
            self.refreshStatus()
            self.updates.checkAutomaticallyIfNeeded(enabled: self.model.settings.checkForUpdatesAutomatically)
        }
        UNUserNotificationCenter.current().delegate = self
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.breakWindows.screensChanged() }
        }
        model.start()
        updates.checkAutomaticallyIfNeeded(enabled: model.settings.checkForUpdatesAutomatically)
        if CommandLine.arguments.contains("--paused") { model.togglePause() }
        if CommandLine.arguments.contains("--settings") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
        }
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if CommandLine.arguments.contains("--preview") { breakWindows.preview() }

    }

    func applicationWillTerminate(_ notification: Notification) {
        updates.stop()
        model?.stop()
        breakWindows?.close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func refreshStatus() {
        let marker = model.isPaused ? "⏸ " : (model.phase.isBreak ? "☕︎ " : "")
        let showsTime = model.settings.showMenuBarTime
        let title = showsTime ? "\(marker)\(model.timeText)" : ""
        if lastStatusTitle != title {
            statusItem.button?.title = title
            lastStatusTitle = title
        }
        if lastShowsTime != showsTime {
            statusItem.button?.imagePosition = showsTime ? .imageLeading : .imageOnly
            statusItem.length = showsTime ? NSStatusItem.variableLength : NSStatusItem.squareLength
            lastShowsTime = showsTime
            if CommandLine.arguments.contains("--diagnostics") {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let button = self.statusItem.button else { return }
                    print("RestFlow menu: showTime=\(showsTime), width=\(button.frame.width)pt, icon=18pt")
                    fflush(stdout)
                }
            }
        }
        // A changing tooltip can linger at the pointer; keep the countdown in the menu instead.
        statusItem.button?.toolTip = nil
        phaseMenuItem?.title = model.menuStatusText
        statusItem.button?.setAccessibilityValue(model.menuStatusText)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updates.checkAutomaticallyIfNeeded(enabled: model.settings.checkForUpdatesAutomatically)
        menu.removeAllItems()
        let phaseItem = NSMenuItem(title: model.menuStatusText, action: nil, keyEquivalent: "")
        phaseItem.isEnabled = false
        menu.addItem(phaseItem)
        phaseMenuItem = phaseItem
        menu.addItem(.separator())
        addItem(model.isPaused ? model.text("继续计时", "Resume timer") : model.text("暂停计时", "Pause timer"),
                action: #selector(togglePause), shortcut: model.settings.pauseShortcut, to: menu)
        addItem(model.text("重新开始", "Restart"), action: #selector(restart), shortcut: model.settings.restartShortcut, to: menu)
        addItem(model.text("现在休息", "Rest now"), action: #selector(restNow), shortcut: model.settings.restNowShortcut, to: menu)
        if model.phase.isBreak { addItem(model.text("提前结束休息", "End break"), action: #selector(endBreak), to: menu) }
        menu.addItem(.separator())
        addItem(model.text("设置…", "Settings…"), action: #selector(showSettings), to: menu)
        addItem(model.text("菜单栏显示时间", "Show time in menu bar"), action: #selector(toggleMenuBarTime),
                checked: model.settings.showMenuBarTime, to: menu)
        addItem(model.text("开机启动", "Launch at login"), action: #selector(toggleLaunchAtLogin),
                checked: model.settings.launchAtLogin, to: menu)
        if model.settings.launchAtLogin && model.loginItem.status == .requiresApproval {
            addItem(model.text("在系统设置中允许启动…", "Allow in System Settings…"), action: #selector(openLoginSettings), to: menu)
        }
        menu.addItem(.separator())
        addItem(model.text("退出 \(AppIdentity.displayName)", "Quit \(AppIdentity.displayName)"), action: #selector(quit), to: menu)
    }

    private func addItem(_ title: String, action: Selector, shortcut: RestFlowCore.KeyboardShortcut? = nil,
                         checked: Bool = false, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = checked ? .on : .off
        if model.isOutsideOperatingHours && [#selector(togglePause), #selector(restNow)].contains(action) { item.isEnabled = false }
        if let shortcut {
            item.keyEquivalent = ShortcutController.keyEquivalent(shortcut)
            item.keyEquivalentModifierMask = ShortcutController.cocoaModifiers(shortcut)
        }
        item.target = self
        menu.addItem(item)
    }

    @objc private func restNow() { breakWindows.restNow() }
    @objc private func togglePause() { model.togglePause() }
    @objc private func restart() { model.restart() }
    @objc private func endBreak() { model.endBreak() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func toggleMenuBarTime() {
        model.settings.showMenuBarTime.toggle()
        showConfigurationErrorIfNeeded()
    }
    @objc private func toggleLaunchAtLogin() {
        model.settings.launchAtLogin.toggle()
        showConfigurationErrorIfNeeded()
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private var settingsTitle: String { "\(AppIdentity.displayName) \(model.text("设置", "Settings"))" }

    private func showConfigurationErrorIfNeeded() {
        guard let error = model.configurationError else { return }
        let alert = NSAlert()
        alert.messageText = model.text("设置未更改", "Setting not changed")
        alert.informativeText = error
        alert.runModal()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, updates: updates) { [weak self] in self?.breakWindows.preview() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = settingsTitle
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.refreshNotificationStatus()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// Exercise the same status refresh path used by the running app, with isolated preferences.
    static func checkMenuIntegration() -> Int32 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-menu-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = AppSettings()
        settings.operatingSchedule.enabled = false
        settings.soundEnabled = false
        settings.checkForUpdatesAutomatically = false
        _ = try? ConfigurationStore(directory: directory).load(orCreate: settings)
        var now: TimeInterval = 100
        let delegate = AppDelegate()
        let loginItem = MenuCheckLoginItem()
        delegate.model = AppModel(directory: directory, loginItem: loginItem, clock: { now })
        delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            delegate.model.stop()
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        delegate.statusItem.menu = menu
        delegate.model.onRefresh = { delegate.refreshStatus() }
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        delegate.refreshStatus()
        check(delegate.statusItem.button?.toolTip == nil, "status refresh never creates a floating countdown tooltip")
        delegate.menuWillOpen(menu)
        check(menu.items.first?.title == "专注：25:00", "menu shows focus countdown")
        func item(_ action: Selector) -> NSMenuItem? { menu.items.first { $0.action == action } }
        func click(_ action: Selector) {
            if let selected = item(action) { _ = NSApp.sendAction(action, to: selected.target, from: selected) }
            delegate.menuWillOpen(menu)
        }
        let settingsIndex = menu.items.firstIndex { $0.action == #selector(showSettings) }!
        check(menu.items[settingsIndex + 1].action == #selector(toggleMenuBarTime) &&
              menu.items[settingsIndex + 2].action == #selector(toggleLaunchAtLogin) &&
              menu.items[settingsIndex + 3].isSeparatorItem && menu.items[settingsIndex + 4].action == #selector(quit),
              "menu toggles sit between Settings and Quit")
        check(item(#selector(toggleMenuBarTime))?.state == .on && item(#selector(toggleLaunchAtLogin))?.state == .off,
              "native checkmarks reflect initial preferences")
        click(#selector(toggleMenuBarTime))
        check(item(#selector(toggleMenuBarTime))?.state == .off && delegate.statusItem.button?.title == "" &&
              (try? ConfigurationStore(directory: directory).load(orCreate: settings).showMenuBarTime) == false,
              "menu action hides time and persists the unchecked preference")
        click(#selector(toggleMenuBarTime))
        check(item(#selector(toggleMenuBarTime))?.state == .on && delegate.statusItem.button?.title == "25:00",
              "menu action restores time and checkmark")
        click(#selector(toggleLaunchAtLogin))
        check(loginItem.status == .enabled && item(#selector(toggleLaunchAtLogin))?.state == .on &&
              (try? ConfigurationStore(directory: directory).load(orCreate: settings).launchAtLogin) == true,
              "menu login action applies and persists using an isolated service")
        click(#selector(toggleLaunchAtLogin))
        check(loginItem.status == .notRegistered && item(#selector(toggleLaunchAtLogin))?.state == .off,
              "menu login action disables and clears the checkmark")
        loginItem.needsApproval = true
        click(#selector(toggleLaunchAtLogin))
        check(item(#selector(openLoginSettings)) != nil && loginItem.status == .requiresApproval,
              "pending login approval provides a System Settings menu entry")
        click(#selector(toggleLaunchAtLogin))
        check(item(#selector(openLoginSettings)) == nil, "disabling login removes the approval entry")
        loginItem.rejectChanges = true
        delegate.model.settings.launchAtLogin = true
        delegate.menuWillOpen(menu)
        check(delegate.model.configurationError != nil && !delegate.model.settings.launchAtLogin &&
              item(#selector(toggleLaunchAtLogin))?.state == .off &&
              (try? ConfigurationStore(directory: directory).load(orCreate: settings).launchAtLogin) == false,
              "failed login registration preserves unchecked preference and saved configuration")
        loginItem.rejectChanges = false
        let accepted = try! Data(contentsOf: directory.appendingPathComponent("config.json"))
        var external = delegate.model.settings
        external.volume = 0.3
        let externalData = try! ConfigurationStore.encode(external)
        try! externalData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        delegate.model.settings.showMenuBarTime = false
        check(delegate.model.configurationError != nil && delegate.model.settings.showMenuBarTime &&
              (try? Data(contentsOf: directory.appendingPathComponent("config.json"))) == externalData,
              "external file conflict rolls back the menu preference without overwriting edits or recursing")
        try! accepted.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        now += 1
        delegate.model.refresh()
        check(menu.items.first?.title == "专注：24:59", "open menu countdown refreshes with the timer")
        delegate.model.settings.showMenuBarTime = false
        check(delegate.statusItem.button?.title == "" && menu.items.first?.title == "专注：24:59", "hidden menu-bar time leaves menu countdown visible")
        delegate.model.startShortBreak()
        check(menu.items.first?.title == "休息：00:30", "menu shows rest countdown")
        delegate.model.settings.showMenuBarTime = true
        check(delegate.statusItem.button?.title == "☕︎ 00:30", "menu-bar rest marker is a language-independent symbol")
        delegate.model.togglePause()
        check(delegate.statusItem.button?.title == "⏸ 00:30", "pause symbol takes precedence while resting")
        delegate.model.togglePause()
        delegate.model.settings.language = .english
        delegate.menuWillOpen(menu)
        check(menu.items.first?.title == "Rest: 00:30", "menu phase label switches to English")
        check(delegate.statusItem.button?.toolTip == nil, "tooltip remains absent after phase and language changes")
        return failures == 0 ? 0 : 1
    }
}

/// Menu diagnostics never register or unregister the user's actual login item.
@MainActor
private final class MenuCheckLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var needsApproval = false
    var rejectChanges = false
    func apply(enabled: Bool) throws {
        if rejectChanges { throw ConfigurationError.invalid("Diagnostic login registration failure") }
        status = enabled ? (needsApproval ? .requiresApproval : .enabled) : .notRegistered
    }
}
