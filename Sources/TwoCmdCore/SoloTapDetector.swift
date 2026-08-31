import CoreGraphics

/// Which physical ⌘ key was tapped.
public enum CommandSide: CaseIterable, Sendable {
    case left
    case right
}

/// State machine recognising a "solo tap" of the left or right ⌘ key: pressed and
/// released with nothing in between.
///
/// Feed it every modifier change, and call `cancel()` for anything else that should
/// void the gesture (normal key presses, mouse clicks, scrolling). That way ⌘C,
/// ⌘Tab, ⌘-click and ⌘⇧ keep working untouched.
public struct SoloTapDetector {
    public enum KeyCode {
        public static let rightCommand: CGKeyCode = 54
        public static let leftCommand: CGKeyCode = 55
    }

    /// Device-dependent modifier flags (`NX_DEVICE*KEYMASK`) per modifier key code.
    /// Device-dependent bits are used instead of `maskCommand` so press and release
    /// of one specific physical key can be told apart (e.g. left ⌘ while right ⌘
    /// is still held).
    static let modifierFlags: [CGKeyCode: UInt64] = [
        54: 0x0000_0010, // right ⌘
        55: 0x0000_0008, // left ⌘
        56: 0x0000_0002, // left ⇧
        57: 0x0001_0000, // caps lock (NX_ALPHASHIFTMASK)
        58: 0x0000_0020, // left ⌥
        59: 0x0000_0001, // left ⌃
        60: 0x0000_0004, // right ⇧
        61: 0x0000_0040, // right ⌥
        62: 0x0000_2000, // right ⌃
        63: 0x0080_0000, // fn (NX_SECONDARYFNMASK)
    ]

    /// Caps lock is a latched state rather than a held key: its bit can stay set
    /// indefinitely, so it must not count as "another modifier is down".
    private static let capsLockKeyCode: CGKeyCode = 57

    /// Every bit belonging to a modifier the user can physically hold down.
    private static let heldModifierMask: UInt64 = modifierFlags
        .filter { $0.key != capsLockKeyCode }
        .values
        .reduce(0) { $0 | $1 }

    /// Modifier key currently held down and still a solo-tap candidate.
    private var pendingKeyCode: CGKeyCode?

    public init() {}

    /// Handles a `flagsChanged` event. Returns the ⌘ side when this completes a solo tap.
    public mutating func modifierChanged(keyCode: CGKeyCode, flags: UInt64) -> CommandSide? {
        guard let flag = Self.modifierFlags[keyCode] else {
            pendingKeyCode = nil
            return nil
        }

        let isKeyDown = flags & flag != 0
        if isKeyDown {
            // Any newly pressed modifier becomes the only candidate, so ⌘⇧ cannot fire.
            pendingKeyCode = keyCode
            return nil
        }

        let wasSoloTap = pendingKeyCode == keyCode
        pendingKeyCode = nil
        // Nothing else may still be held: holding one ⌘ and tapping the other, or
        // releasing ⌘ out of a ⌥⌘ combo, is not a solo tap.
        let noOtherModifiersHeld = flags & Self.heldModifierMask == 0
        guard wasSoloTap, noOtherModifiersHeld else { return nil }
        return Self.side(for: keyCode)
    }

    /// Voids the pending gesture: a real key, a click or a scroll happened.
    public mutating func cancel() {
        pendingKeyCode = nil
    }

    private static func side(for keyCode: CGKeyCode) -> CommandSide? {
        switch keyCode {
        case KeyCode.leftCommand: return .left
        case KeyCode.rightCommand: return .right
        default: return nil
        }
    }
}
