import AppKit
import SwiftUI

@MainActor
final class BreakWindowController {
    private let model: AppModel
    private var windows: [UInt32: NSWindow] = [:]
    private var isPreview = false
    private var previousApplication: NSRunningApplication?

    init(model: AppModel) { self.model = model }

    func sync() {
        if model.phase.isBreak {
            isPreview = false
            showAllScreens()
        } else {
            close()
        }
    }

    func preview() {
        guard !model.phase.isBreak else { showAllScreens(); return }
        model.prepareBreakContent()
        isPreview = true
        showAllScreens()
    }

    func screensChanged() {
        guard isPreview || model.phase.isBreak else { return }
        showAllScreens()
    }

    func updateTitles() {
        windows.values.forEach { $0.title = model.text("RestFlow 休息", "RestFlow Break") }
    }

    func close() {
        let hadWindows = !windows.isEmpty
        let old = windows.values
        windows.removeAll()
        old.forEach { $0.close() }
        isPreview = false
        if hadWindows { previousApplication?.activate(options: [.activateIgnoringOtherApps]) }
        previousApplication = nil
    }

    private func showAllScreens() {
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
                window.isOpaque = true
                window.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.105, blue: 0.09, alpha: 1)
                window.hidesOnDeactivate = false
                (window as? BreakOverlayWindow)?.escapeAction = { [weak self] in
                    guard let self else { return }
                    if self.isPreview { self.close() } else { self.model.endBreak() }
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.values.first?.makeKeyAndOrderFront(nil)
    }

    private func makeView() -> BreakView {
        BreakView(model: model, isPreview: isPreview, closePreview: { [weak self] in self?.close() })
    }
}

private final class BreakOverlayWindow: NSWindow {
    var escapeAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escapeAction?() }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { escapeAction?() }
}
