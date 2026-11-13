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
        if CommandLine.arguments.contains("--check-settings-integration") { exit(Int32(SettingsIntegrationChecks.run())) }
        if CommandLine.arguments.contains("--check-wellbeing-integration") { exit(WellbeingIntegrationChecks.run()) }
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
    private var noiseMenu: FocusNoiseMenu?
    private var noiseToggleMenuItem: NSMenuItem?
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
            case .focusNoise: self?.toggleFocusNoise()
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
        // Expose the exact status menu for UI regression with an isolated --config-dir.
        if args.contains("--debug-menu") {
            showSettings()
            let button = NSButton(title: "Status menu (debug)", target: self, action: #selector(showDebugMenu(_:)))
            button.frame = NSRect(x: 20, y: 8, width: 180, height: 28)
            settingsWindow?.contentView?.addSubview(button)
        }
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
        noiseToggleMenuItem?.state = model.isFocusNoiseEnabled ? .on : .off
        noiseMenu?.refresh()
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
        addItem(model.text("设置…", "Settings…"), action: #selector(showSettings), to: menu)
        addItem(model.text("启用白噪音", "Enable white noise"), action: #selector(toggleFocusNoise),
                shortcut: model.settings.focusNoiseShortcut, checked: model.isFocusNoiseEnabled, to: menu)
        noiseToggleMenuItem = menu.items.last
        let choices = FocusNoiseMenu(model: model) { [weak self] in self?.showConfigurationErrorIfNeeded() }
        let choicesItem = NSMenuItem(title: model.text("更换白噪音", "Change white noise"), action: nil, keyEquivalent: "")
        choicesItem.submenu = choices.menu
        menu.addItem(choicesItem)
        noiseMenu = choices
        addItem(model.text("现在休息", "Rest now"), action: #selector(restNow), shortcut: model.settings.restNowShortcut, to: menu)
        addItem(model.isPaused ? model.text("继续计划", "Resume plan") : model.text("暂停计划", "Pause plan"),
                action: #selector(togglePause), shortcut: model.settings.pauseShortcut, to: menu)
        addItem(model.text("重新开始", "Restart"), action: #selector(restart), shortcut: model.settings.restartShortcut, to: menu)
        if model.settings.deferEnabled && !model.phase.isBreak {
            addItem(model.text("延后 3 分钟", "Delay break by 3 minutes"), action: #selector(deferBreak), to: menu)
        }
        if model.phase.isBreak { addItem(model.text("提前结束休息", "End break"), action: #selector(endBreak), to: menu) }
        menu.addItem(.separator())
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
        if (model.isOutsideOperatingHours || model.isAway) && [#selector(togglePause), #selector(restNow)].contains(action) { item.isEnabled = false }
        if let shortcut {
            item.keyEquivalent = ShortcutController.keyEquivalent(shortcut)
            item.keyEquivalentModifierMask = ShortcutController.cocoaModifiers(shortcut)
        }
        if action == #selector(deferBreak) { item.isEnabled = model.canDefer }
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleFocusNoise() { model.toggleFocusNoise(); showConfigurationErrorIfNeeded() }
    @objc private func showDebugMenu(_ sender: NSButton) {
        guard let menu = statusItem.menu else { return }
        menuWillOpen(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
    @objc private func deferBreak() { model.deferBreak() }
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

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let token = response.notification.request.content.userInfo["focusToken"] as? String
        if response.actionIdentifier == FeedbackService.deferAction, let token {
            Task { @MainActor [weak self] in
                self?.model.deferBreak(token: token)
                completionHandler()
            }
        } else { completionHandler() }
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
        check(item(#selector(toggleFocusNoise))?.state == .off, "white noise menu toggle defaults to unchecked")
        delegate.model.togglePause() // Exercise preferences without playing audible diagnostic noise.
        click(#selector(toggleFocusNoise))
        check(item(#selector(toggleFocusNoise))?.state == .on && delegate.model.settings.focusNoiseRandom,
              "native noise menu action enables and checks a default random mix")
        delegate.model.settings.focusNoiseShortcut = RestFlowCore.KeyboardShortcut(keyCode: 45, modifiers: 6144)
        delegate.menuWillOpen(menu)
        check(item(#selector(toggleFocusNoise))?.keyEquivalent == "n" &&
              item(#selector(toggleFocusNoise))?.keyEquivalentModifierMask == [.control, .option],
              "noise menu item renders the configured native keyboard modifiers")
        click(#selector(toggleFocusNoise))
        check(item(#selector(toggleFocusNoise))?.state == .off &&
              (try? ConfigurationStore(directory: directory).load(orCreate: settings).focusNoiseEnabled) == false,
              "native noise action disables and persists the unchecked preference")
        let actionItems = menu.items.filter { !$0.isSeparatorItem }.dropFirst()
        let primary = Array(actionItems.prefix(6))
        check(primary.count == 6 && primary[0].action == #selector(showSettings) &&
              primary[1].action == #selector(toggleFocusNoise) && primary[2].submenu === delegate.noiseMenu?.menu &&
              primary[3].action == #selector(restNow) && primary[4].action == #selector(togglePause) &&
              primary[5].action == #selector(restart),
              "primary menu order is Settings, Enable noise, Change noise, Rest now, Pause plan, Restart")
        check(item(#selector(togglePause))?.title == "继续计划", "paused plan offers Resume plan")
        let noiseMenu = delegate.noiseMenu!.menu
        check(noiseMenu.items.filter { !$0.isSeparatorItem }.count == 13,
              "hover submenu contains Random and exactly twelve specific noises")
        check(noiseMenu.items.allSatisfy { $0.action == nil },
              "submenu controls own clicks without duplicate menu-item actions that close tracking")
        func selectNoise(_ id: String) {
            let selected = noiseMenu.items.first { $0.representedObject as? String == id }!
            (selected.view as! NoiseMenuRow).button.performClick(nil)
        }
        func noiseState(_ id: String) -> NSControl.StateValue? {
            noiseMenu.items.first { $0.representedObject as? String == id }?.state
        }
        delegate.model.settings.focusNoiseRandomCount = 2
        selectNoise(AppSettings.randomSoundID)
        let firstMix = delegate.model.resolvedNoiseIDs
        check(delegate.model.settings.focusNoiseEnabled && firstMix.count == 2 &&
              noiseState(AppSettings.randomSoundID) == .on && item(#selector(toggleFocusNoise))?.state == .on,
              "submenu Random enables noise with the saved mix count and updates parent checkmark")
        selectNoise(AppSettings.randomSoundID)
        check(delegate.model.settings.focusNoiseRandomCount == 2 &&
              Set(firstMix).isDisjoint(with: delegate.model.resolvedNoiseIDs),
              "clicking checked Random rerolls immediately without changing the saved count")
        selectNoise("lightRain"); selectNoise("stream")
        check(!delegate.model.settings.focusNoiseRandom && delegate.model.settings.focusNoiseIDs == ["lightRain", "stream"] &&
              noiseState("lightRain") == .on && noiseState("stream") == .on && noiseState(AppSettings.randomSoundID) == .off,
              "submenu controls switch from random to manual and allow consecutive multiselection")
        selectNoise("lightRain")
        check(delegate.model.settings.focusNoiseIDs == ["stream"] && noiseState("lightRain") == .off,
              "clicking a selected specific noise removes only that layer")
        selectNoise("stream")
        check(!delegate.model.settings.focusNoiseEnabled && delegate.model.settings.focusNoiseIDs.isEmpty &&
              item(#selector(toggleFocusNoise))?.state == .off,
              "deselecting the last noise disables playback and unchecks the parent")
        check(delegate.noiseMenu?.menu === noiseMenu && noiseMenu.items.first?.view is NoiseMenuRow,
              "multiple selections retain the same custom controls and native submenu")
        check((try? ConfigurationStore(directory: directory).load(orCreate: settings).focusNoiseIDs) == [],
              "submenu changes persist to the isolated configuration")
        delegate.model.settings.focusNoiseShortcut = nil
        delegate.model.togglePause()
        delegate.menuWillOpen(menu)
        check(item(#selector(deferBreak))?.isEnabled == true, "menu offers a single three-minute delay during running focus")
        click(#selector(deferBreak))
        check(delegate.model.timeText == "28:00" && item(#selector(deferBreak))?.isEnabled == false,
              "native delay action extends focus and disables repeat delay")
        delegate.model.restart()
        delegate.menuWillOpen(menu)
        let settingsIndex = menu.items.firstIndex { $0.action == #selector(showSettings) }!
        let timeIndex = menu.items.firstIndex { $0.action == #selector(toggleMenuBarTime) }!
        check(timeIndex > settingsIndex && menu.items[timeIndex + 1].action == #selector(toggleLaunchAtLogin) &&
              menu.items[timeIndex + 2].isSeparatorItem && menu.items[timeIndex + 3].action == #selector(quit),
              "persistent checkmark preferences stay below primary actions and above Quit")
        check(item(#selector(togglePause))?.title == "暂停计划", "running plan offers Pause plan")
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
        check(menu.items.contains { $0.title == "Change white noise" } &&
              delegate.noiseMenu?.menu.items.contains { $0.title == "Cracking thunder" } == true,
              "noise submenu and renamed thunder switch to English with the interface")
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
