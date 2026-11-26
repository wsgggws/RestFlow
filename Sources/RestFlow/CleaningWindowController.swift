import AppKit
import SwiftUI
import RestFlowCore

struct CleaningScreen {
    let id: UInt32
    let frame: NSRect
    var screen: NSScreen? = nil

    static var current: [CleaningScreen] {
        NSScreen.screens.enumerated().map { index, screen in
            CleaningScreen(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? UInt32(index),
                           frame: screen.frame, screen: screen)
        }
    }
}

@MainActor
final class CleaningWindowController {
    private let model: AppModel
    private let input: any CleaningInputProtecting
    private let screens: () -> [CleaningScreen]
    private var windows: [UInt32: NSWindow] = [:]
    private let presentation = CleaningPresentation()
    private var previousOptions: NSApplication.PresentationOptions?
    private var previousApplication: NSRunningApplication?
    private var previousShortcutSuspension = false
    private var cursorHidden = false
    var onError: ((CleaningProtectionError) -> Void)?
    var windowCount: Int { windows.count }

    init(model: AppModel, input: (any CleaningInputProtecting)? = nil,
         screens: @escaping () -> [CleaningScreen] = { CleaningScreen.current }) {
        self.model = model; self.input = input ?? CleaningInputGuard(); self.screens = screens
        model.onCleaningInterruption = { [weak self] in self?.stop(restoreApplication: false) }
    }

    func start() throws {
        guard !model.isCleaning, !model.isPreview, !model.phase.isBreak else { return }
        guard !screens().isEmpty else { throw CleaningProtectionError.unavailable }
        do {
            try input.start(progress: { [weak self] value, waiting in
                self?.presentation.update(progress: value, waiting: waiting)
            }, exit: { [weak self] in self?.stop() }, failure: { [weak self] error in
                guard let self else { return }
                self.stop(restoreApplication: false)
                if let error { self.onError?(error) }
            })
        } catch { input.stop(); throw error }
        guard model.beginCleaning() else { input.stop(); return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousOptions = NSApp.presentationOptions
        previousShortcutSuspension = model.shortcuts.isSuspended
        model.shortcuts.isSuspended = true
        var options = NSApp.presentationOptions
        options.subtract([.autoHideDock, .autoHideMenuBar])
        options.formUnion([.hideDock, .hideMenuBar])
        NSApp.presentationOptions = options
        presentation.update(progress: 0, waiting: false)
        reconcileScreens()
        if model.isCleaning {
            NSApp.activate(ignoringOtherApps: true)
            windows.values.first?.makeKeyAndOrderFront(nil)
            NSCursor.hide(); cursorHidden = true
        }
    }

    func reconcileScreens() {
        guard model.isCleaning else { return }
        let screens = screens()
        guard !screens.isEmpty else { stop(restoreApplication: false); return }
        var live = Set<UInt32>()
        for screen in screens {
            let id = screen.id
            live.insert(id)
            let window: NSWindow
            if let current = windows[id] { window = current }
            else {
                window = CleaningOverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                               backing: .buffered, defer: false, screen: screen.screen)
                window.isReleasedWhenClosed = false
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.isOpaque = true
                window.backgroundColor = .black
                window.hidesOnDeactivate = false
                windows[id] = window
            }
            window.setFrame(screen.frame, display: true)
            window.title = model.text("屏幕键盘护理", "Screen & keyboard cleaning")
            window.contentView = NSHostingView(rootView: CleaningView(presentation: presentation, language: model.settings.language))
            window.orderFrontRegardless()
        }
        for id in Set(windows.keys).subtracting(live) { windows.removeValue(forKey: id)?.close() }
    }

    func stop(restoreApplication: Bool = true) {
        input.stop()
        let hadSession = previousOptions != nil
        let old = windows.values
        windows.removeAll()
        old.forEach { $0.close() }
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        if let previousOptions { NSApp.presentationOptions = previousOptions }
        previousOptions = nil
        if hadSession { model.shortcuts.isSuspended = previousShortcutSuspension }
        model.endCleaning()
        if hadSession && restoreApplication && previousApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate(options: [.activateIgnoringOtherApps])
        }
        previousApplication = nil
    }
}

@MainActor
private final class CleaningPresentation: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var waiting = false

    func update(progress: Double, waiting: Bool) {
        if self.progress != progress { self.progress = progress }
        if self.waiting != waiting { self.waiting = waiting }
    }
}

private struct CleaningView: View {
    @ObservedObject var presentation: CleaningPresentation
    let language: AppLanguage

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Text(language.text("屏幕键盘护理", "Screen & keyboard cleaning"))
                    .font(.system(size: 20, weight: .light))
                Text(presentation.waiting
                     ? language.text("松开所有按键和鼠标按钮后退出", "Release all keys and mouse buttons to exit")
                     : language.text("按住 Esc 3 秒退出", "Hold Esc for 3 seconds to exit"))
                    .font(.system(size: 14)).foregroundStyle(.gray)
                ProgressView(value: presentation.progress).tint(.gray).frame(width: 160)
                    .opacity(presentation.progress > 0 ? 1 : 0)
            }.foregroundStyle(Color(white: 0.65))
        }.ignoresSafeArea().preferredColorScheme(.dark)
    }
}

/// Also consumes app-directed synthetic input that can bypass the session event tap.
private final class CleaningOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}
