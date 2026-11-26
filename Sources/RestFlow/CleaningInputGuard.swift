import AppKit
import ApplicationServices
import Carbon
import RestFlowCore

enum CleaningProtectionError: Error {
    case accessibilityRequired, secureInput, unavailable, interrupted

    func message(in language: AppLanguage) -> String {
        switch self {
        case .accessibilityRequired:
            return language.text("请在系统设置中允许 RestFlow 使用辅助功能，再重新开启护理。权限仅用于临时拦截输入，不记录按键内容。",
                                 "Allow RestFlow in System Settings → Accessibility, then start cleaning again. Access is used only to temporarily block input; keystrokes are not recorded.")
        case .secureInput:
            return language.text("系统正在使用安全键盘输入（例如终端的“安全键盘输入”）。请先关闭该功能后重试。",
                                 "Secure keyboard input is active, for example Terminal’s Secure Keyboard Entry. Turn it off before starting cleaning.")
        case .unavailable:
            return language.text("无法建立输入保护，未进入护理模式。请检查辅助功能权限后重试。",
                                 "Input protection could not be established. Cleaning was not started. Check Accessibility access and try again.")
        case .interrupted:
            return language.text("输入保护已中断，护理模式已退出。", "Input protection was interrupted. Cleaning has ended.")
        }
    }
}

@MainActor
protocol CleaningInputProtecting: AnyObject {
    func start(progress: @escaping (Double, Bool) -> Void, exit: @escaping () -> Void,
               failure: @escaping (CleaningProtectionError?) -> Void) throws
    func stop()
}

/// Active session tap, attached only to the main run loop and destroyed on every exit.
@MainActor
final class CleaningInputGuard: CleaningInputProtecting {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var gesture = CleaningExitGesture()
    private var progress: ((Double, Bool) -> Void)?
    private var exit: (() -> Void)?
    private var failure: ((CleaningProtectionError?) -> Void)?
    private var completionQueued = false
    private var generation = UUID()
    private var nextPermissionCheck: TimeInterval = 0
    private let trusted: () -> Bool
    private let secureInput: () -> Bool
    private let clock: () -> TimeInterval

    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
    private static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    static let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged,
        .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!]

    init(trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.trusted = trusted; self.secureInput = secureInput; self.clock = clock
    }

    deinit {
        // The C callback uses an unretained context, so it must never outlive this object.
        timer?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopSourceInvalidate(source) }
    }

    func start(progress: @escaping (Double, Bool) -> Void, exit: @escaping () -> Void,
               failure: @escaping (CleaningProtectionError?) -> Void) throws {
        stop()
        guard trusted() else { throw CleaningProtectionError.accessibilityRequired }
        guard !secureInput() else { throw CleaningProtectionError.secureInput }
        let mask = Self.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let guarder = Unmanaged<CleaningInputGuard>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guarder.consume(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw CleaningProtectionError.unavailable }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw CleaningProtectionError.unavailable
        }
        self.tap = tap; self.source = source
        self.progress = progress; self.exit = exit; self.failure = failure
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); throw CleaningProtectionError.unavailable }
        reconcilePhysicalState()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Emergency system actions remain available, even when every ordinary event is dropped.
    static func isEmergency(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection(modifierMask)
        return (code == 53 && flags == [.maskCommand, .maskAlternate]) ||
               (code == 12 && flags == [.maskCommand, .maskControl])
    }

    enum Disposition { case blocked, emergency, failed }

    static func route(type: CGEventType, event: CGEvent, gesture: inout CleaningExitGesture, at now: TimeInterval) -> Disposition {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return .failed
        }
        if isEmergency(type: type, event: event) { return .emergency }
        switch type {
        case .keyDown, .keyUp:
            gesture.setModifiers(event.flags.intersection(Self.modifierMask).rawValue, at: now)
            gesture.key(UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), down: type == .keyDown, at: now)
        case .flagsChanged:
            gesture.setModifiers(event.flags.intersection(Self.modifierMask).rawValue, at: now)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
            gesture.button(Int(event.getIntegerValueField(.mouseEventButtonNumber)), down: down, at: now)
        default: break
        }
        return .blocked
    }

    private func consume(type: CGEventType, event: CGEvent) -> Bool {
        switch Self.route(type: type, event: event, gesture: &gesture, at: clock()) {
        case .blocked: publishGesture(); return true
        case .emergency:
            // Let macOS confirm screen lock before restoring any timer/audio state.
            // Force Quit needs immediate cleanup so its system dialog can accept input.
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 { queueCompletion(failed: true, emergency: true) }
            return false
        case .failed: queueCompletion(failed: true); return false
        }
    }

    private func tick() {
        guard let tap else { return }
        guard CGEvent.tapIsEnabled(tap: tap), !secureInput() else { queueCompletion(failed: true); return }
        if clock() >= nextPermissionCheck {
            nextPermissionCheck = clock() + 1
            guard trusted() else { queueCompletion(failed: true); return }
        }
        reconcilePhysicalState()
        publishGesture()
    }

    private func reconcilePhysicalState() {
        let keys = Set((UInt16(0)..<128).filter {
            !Self.modifierKeys.contains($0) && CGEventSource.keyState(.hidSystemState, key: $0)
        })
        let buttons = Set((0..<32).filter { CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32($0))!) })
        gesture.reconcile(keys: keys, buttons: buttons,
                          modifiers: CGEventSource.flagsState(.hidSystemState).intersection(Self.modifierMask).rawValue, at: clock())
    }

    private func publishGesture() {
        progress?(gesture.progress, gesture.waitingForRelease)
        if gesture.shouldExit { queueCompletion(failed: false) }
    }

    private func queueCompletion(failed: Bool, emergency: Bool = false) {
        guard !completionQueued else { return }
        completionQueued = true
        let generation = generation
        // Never invalidate the event tap or reactivate another app inside its C callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tap != nil, self.generation == generation else { return }
            if failed { self.failure?(emergency ? nil : .interrupted) } else { self.exit?() }
        }
    }

    func stop() {
        generation = UUID(); completionQueued = false; nextPermissionCheck = 0
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
        gesture = CleaningExitGesture()
        progress = nil; exit = nil; failure = nil
    }
}
