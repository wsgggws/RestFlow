import AppKit
import SwiftUI

@MainActor
final class BreakWindowController {
    private let model: AppModel
    private var windows: [UInt32: NSWindow] = [:]
    private var compactPresentation = false
    private let inputGuard = BreakInputGuard()
    private var previousApplication: NSRunningApplication?

    init(model: AppModel) { self.model = model }

    func sync() {
        if model.phase.isBreak {
            showAllScreens()
        } else {
            close()
        }
    }

    func preview() {
        guard !model.phase.isBreak else { showAllScreens(); return }
        compactPresentation = true
        model.startShortBreak()
        if windows.isEmpty { showAllScreens() }
    }

    func screensChanged() {
        guard model.phase.isBreak else { return }
        showAllScreens()
    }

    func updateTitles() {
        windows.values.forEach { $0.title = model.text("RestFlow 休息", "RestFlow Break") }
    }

    func reconcilePresentation() {
        let shouldShow = model.settings.showsBreakScreen(for: model.phase)
        if shouldShow != !windows.isEmpty { sync() }
    }

    func close() {
        inputGuard.stop()
        model.shortcuts.isSuspended = false
        let hadWindows = !windows.isEmpty
        let old = windows.values
        windows.removeAll()
        old.forEach { $0.close() }
        compactPresentation = false
        if hadWindows { previousApplication?.activate(options: [.activateIgnoringOtherApps]) }
        previousApplication = nil
    }

    private func showAllScreens() {
        guard model.settings.showsBreakScreen(for: model.phase) else { close(); return }
        if windows.isEmpty {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication = frontmost
            }
        }
        var activeIDs = Set<UInt32>()
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                ?? UInt32(index)
            activeIDs.insert(id)
            let window: NSWindow
            if let existing = windows[id] { window = existing }
            else {
                window = BreakOverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false, screen: screen)
                window.title = "RestFlow 休息"
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hidesOnDeactivate = false
                (window as? BreakOverlayWindow)?.escapeAction = { [weak self] in
                    guard let self else { return }
                    self.model.endBreak()
                }
                windows[id] = window
            }
            window.setFrame(screen.frame, display: true)
            window.title = model.text("RestFlow 休息", "RestFlow Break")
            // Existing windows already observe the shared model; avoid rebuilding animations each tick.
            if let host = window.contentView as? NSHostingView<BreakView> {
                host.rootView = makeView()
            } else {
                window.contentView = NSHostingView(rootView: makeView())
            }
            window.orderFrontRegardless()
        }
        for id in Set(windows.keys).subtracting(activeIDs) {
            windows.removeValue(forKey: id)?.close()
        }
        model.shortcuts.isSuspended = true
        if !inputGuard.start(escape: { [weak self] in self?.model.endBreak() }) {
            model.configurationError = model.text("全局 Esc 被其他应用占用；休息窗口内仍可按 Esc 或点击退出。", "Global Esc is in use by another app. Press Esc inside the break window or click Esc to exit.")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.values.first?.makeKeyAndOrderFront(nil)
    }

    private func makeView() -> BreakView {
        BreakView(model: model, compact: compactPresentation)
    }
}

private final class BreakOverlayWindow: NSWindow {
    var escapeAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escapeAction?() }
        // Other keys are consumed while resting.
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { escapeAction?() }
        return true
    }

    override func cancelOperation(_ sender: Any?) { escapeAction?() }
}
