import Foundation

/// Transient physical key state only: no characters, history, or persistence.
public struct CleaningExitGesture {
    public static let escapeKey: UInt16 = 53
    public static let holdDuration: TimeInterval = 3
    private var keys: Set<UInt16> = []
    private var buttons: Set<Int> = []
    private var modifiers: UInt64 = 0
    private var beganAt: TimeInterval?
    public private(set) var progress: Double = 0
    public private(set) var waitingForRelease = false
    public var shouldExit: Bool { waitingForRelease && keys.isEmpty && buttons.isEmpty && modifiers == 0 }

    public init() {}

    public mutating func key(_ code: UInt16, down: Bool, at time: TimeInterval) {
        advance(at: time)
        if down { keys.insert(code) } else { keys.remove(code) }
        advance(at: time)
    }

    public mutating func button(_ number: Int, down: Bool, at time: TimeInterval) {
        advance(at: time)
        if down { buttons.insert(number) } else { buttons.remove(number) }
        advance(at: time)
    }

    public mutating func setModifiers(_ flags: UInt64, at time: TimeInterval) {
        advance(at: time)
        modifiers = flags
        advance(at: time)
    }

    public mutating func reconcile(keys: Set<UInt16>, buttons: Set<Int>, modifiers: UInt64, at time: TimeInterval) {
        self.keys = keys; self.buttons = buttons; self.modifiers = modifiers
        advance(at: time)
    }

    public mutating func advance(at time: TimeInterval) {
        guard !waitingForRelease else { return }
        guard keys == [Self.escapeKey], buttons.isEmpty, modifiers == 0 else {
            beganAt = nil; progress = 0; return
        }
        if beganAt == nil { beganAt = time }
        progress = max(0, min(1, (time - beganAt!) / Self.holdDuration))
        if progress >= 1 { waitingForRelease = true }
    }
}
