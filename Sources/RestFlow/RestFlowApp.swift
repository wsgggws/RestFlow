import AppKit
import SwiftUI
import UserNotifications

@main
enum RestFlowApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
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
    private var updateMenuItem: NSMenuItem?
    private var lastShowsTime: Bool?
    private var lastStatusTitle: String?
    private var breakWindows: BreakWindowController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        breakWindows = BreakWindowController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { _ in
            NSColor.black.setFill()
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: 2, y: 3))
            leaf.curve(to: NSPoint(x: 12, y: 12), controlPoint1: NSPoint(x: 0, y: 11), controlPoint2: NSPoint(x: 5, y: 14))
            leaf.curve(to: NSPoint(x: 2, y: 3), controlPoint1: NSPoint(x: 14, y: 5), controlPoint2: NSPoint(x: 10, y: 1))
            leaf.fill()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 1, y: 1))
            stem.line(to: NSPoint(x: 9, y: 9))
            stem.lineWidth = 1.2
            NSColor.black.setStroke()
            stem.stroke()
            return true
        }
        icon.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel("RestFlow")
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
            self.settingsWindow?.title = self.model.text("RestFlow 设置", "RestFlow Settings")
            self.breakWindows.updateTitles()
            self.refreshStatus()
            self.refreshUpdateMenu()
            self.updates.checkAutomaticallyIfNeeded(enabled: self.model.settings.checkForUpdatesAutomatically)
        }
        updates.onChange = { [weak self] in self?.refreshUpdateMenu() }
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
        let marker = model.isPaused ? "⏸ " : (model.phase.isBreak ? model.text("休 ", "Break ") : "")
        let showsTime = model.settings.showMenuBarTime
        let title = showsTime ? "\(marker)\(model.timeText)" : ""
        if lastStatusTitle != title {
            statusItem.button?.title = title
            lastStatusTitle = title
        }
        if lastShowsTime != showsTime {
            statusItem.button?.imagePosition = showsTime ? .imageLeading : .imageOnly
            statusItem.length = showsTime ? NSStatusItem.variableLength : 18
            lastShowsTime = showsTime
            if CommandLine.arguments.contains("--diagnostics") {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let button = self.statusItem.button else { return }
                    print("RestFlow menu: showTime=\(showsTime), width=\(button.frame.width)pt, icon=14pt")
                    fflush(stdout)
                }
            }
        }
        statusItem.button?.toolTip = "RestFlow · \(model.phaseTitle) · \(model.timeText)" +
            (model.isPaused ? model.text(" · 已暂停", " · Paused") : "")
    }

    func menuWillOpen(_ menu: NSMenu) {
        updates.checkAutomaticallyIfNeeded(enabled: model.settings.checkForUpdatesAutomatically)
        menu.removeAllItems()
        let version = NSMenuItem(title: "RestFlow \(updates.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let update = NSMenuItem(title: updates.status(in: model.settings.language), action: #selector(checkOrOpenUpdate), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        updateMenuItem = update
        refreshUpdateMenu()
        menu.addItem(.separator())
        let summary = NSMenuItem(title: "\(model.phaseTitle) · \(model.timeText)", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        addItem(model.isPaused ? model.text("继续计时", "Resume timer") : model.text("暂停计时", "Pause timer"),
                action: #selector(togglePause), to: menu)
        addItem(model.text("重新开始", "Restart"), action: #selector(restart), to: menu)
        if model.phase.isBreak { addItem(model.text("提前结束休息", "End break"), action: #selector(endBreak), to: menu) }
        menu.addItem(.separator())
        addItem(model.text("设置…", "Settings…"), action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        addItem(model.text("退出 RestFlow", "Quit RestFlow"), action: #selector(quit), to: menu)
    }

    private func refreshUpdateMenu() {
        updateMenuItem?.title = updates.status(in: model.settings.language)
        if case .checking = updates.state { updateMenuItem?.isEnabled = false }
        else { updateMenuItem?.isEnabled = true }
    }

    @objc private func checkOrOpenUpdate() {
        if case .available = updates.state { updates.openRelease() }
        else { updates.check() }
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func togglePause() { model.togglePause() }
    @objc private func restart() { model.restart() }
    @objc private func endBreak() { model.endBreak() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, updates: updates) { [weak self] in self?.breakWindows.preview() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = model.text("RestFlow 设置", "RestFlow Settings")
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
}
