import Foundation

/// Physical macOS key code and Carbon modifier mask; independent of keyboard layout.
public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    public func validate() throws {
        let allowed: UInt32 = 256 | 512 | 2048 | 4096
        guard keyCode <= 126, modifiers & ~allowed == 0,
              modifiers & (256 | 2048 | 4096) != 0,
              ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode), keyCode != 53 else {
            throw ConfigurationError.invalid("Use Command, Control or Option with a key (Esc is reserved).")
        }
    }
}
