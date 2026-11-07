import AppKit
import Carbon
import SwiftUI
import RestFlowCore

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let keyPath: WritableKeyPath<AppSettings, RestFlowCore.KeyboardShortcut?>

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.controller = model.shortcuts
        button.language = model.settings.language
        button.shortcut = model.settings[keyPath: keyPath]
        button.commit = { model.settings[keyPath: keyPath] = $0 }
        button.refreshTitle()
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.endRecording() }
}

@MainActor
final class RecorderButton: NSButton {
    weak var controller: ShortcutController?
    var language = AppLanguage.simplifiedChinese
    var shortcut: RestFlowCore.KeyboardShortcut?
    var commit: ((RestFlowCore.KeyboardShortcut) -> Void)?
    private var recording = false
    private var hotKeyMode: UnsafeMutableRawPointer?
    private var resignObserver: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        title = recording ? language.text("请按快捷键…（Esc 取消）", "Press shortcut… (Esc cancels)") :
            shortcut.map { ShortcutController.label($0) } ?? language.text("录入快捷键", "Record shortcut")
        setAccessibilityLabel(title)
    }
    @objc func beginRecording() {
        guard !recording else { return }
        window?.makeFirstResponder(self)
        recording = true
        hotKeyMode = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
        controller?.isRecording = true
        controller?.recordingHandler = { [weak self] shortcut in self?.accept(shortcut) }
        refreshTitle()
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        if let mode = hotKeyMode { PopSymbolicHotKeyMode(mode) }
        hotKeyMode = nil
        controller?.isRecording = false
        controller?.recordingHandler = nil
        refreshTitle()
    }
    override func resignFirstResponder() -> Bool { endRecording(); return super.resignFirstResponder() }
    override func viewDidMoveToWindow() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endRecording() }
            }
        } else { endRecording() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { endRecording(); return }
        accept(RestFlowCore.KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: ShortcutController.carbonModifiers(event.modifierFlags)))
    }
    private func accept(_ shortcut: RestFlowCore.KeyboardShortcut) {
        endRecording()
        commit?(shortcut)
    }
}
