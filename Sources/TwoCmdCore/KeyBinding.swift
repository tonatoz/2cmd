import CoreGraphics
import Foundation

/// A physical key and the system input source it selects. Nil values are draft-only,
/// except when no default input source exists on first launch.
public struct KeyBinding: Codable, Equatable, Sendable {
    public var keyCode: CGKeyCode?
    public var sourceID: String?

    public init(keyCode: CGKeyCode?, sourceID: String?) {
        self.keyCode = keyCode
        self.sourceID = sourceID
    }
}

public enum BindingValidationError: Error, Equatable {
    case count
    case missingKey(Int)
    case unsupportedKey(Int)
    case duplicateKey(Int, Int)
    case missingSource(Int)
}

public enum BindingConfiguration {
    public static let requiredCount = 2
    public static let maximumCount = 5

    public static func standard(leftSourceID: String?, rightSourceID: String?) -> [KeyBinding] {
        [
            KeyBinding(keyCode: 55, sourceID: leftSourceID),
            KeyBinding(keyCode: 54, sourceID: rightSourceID),
        ]
    }

    public static func validationError(
        in bindings: [KeyBinding], allowUnconfiguredRequiredRows: Bool = false
    ) -> BindingValidationError? {
        guard (requiredCount...maximumCount).contains(bindings.count) else { return .count }
        for (index, binding) in bindings.enumerated() {
            guard let keyCode = binding.keyCode else { return .missingKey(index) }
            guard KeyboardKey.isAssignable(keyCode) else { return .unsupportedKey(index) }
            if let previous = bindings[..<index].firstIndex(where: { $0.keyCode == keyCode }) {
                return .duplicateKey(index, previous)
            }
            guard let sourceID = binding.sourceID, !sourceID.isEmpty else {
                if allowUnconfiguredRequiredRows, index < requiredCount, binding.sourceID == nil {
                    continue
                }
                return .missingSource(index)
            }
        }
        return nil
    }
}

/// Stable physical-key labels, independent of the active input source.
public enum KeyboardKey {
    public static let modifierFlags: [CGKeyCode: UInt64] = [
        54: 0x10, 55: 0x08, 58: 0x20, 59: 0x01, 61: 0x40, 62: 0x2000,
    ]

    // Device-dependent held bits plus generic flags cover synthetic events too.
    // Caps Lock is latched, so it deliberately does not count as a held modifier.
    public static let heldModifierMask: UInt64 =
        0x08 | 0x10 | 0x02 | 0x04 | 0x20 | 0x40 | 0x01 | 0x2000 | 0x0080_0000
        | CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    public static func isAssignable(_ keyCode: CGKeyCode) -> Bool {
        names[keyCode] != nil
    }

    public static func isModifier(_ keyCode: CGKeyCode) -> Bool {
        modifierFlags[keyCode] != nil
    }

    /// macOS marks these ordinary keys as function events even without physical Fn.
    public static func hasIntrinsicFunctionFlag(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
        case 64, 79, 80, 90, 96, 97, 98, 99, 100, 101, 103, 105, 106, 107,
            109, 111, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123,
            124, 125, 126:
            return true
        default:
            return false
        }
    }

    public static func name(for keyCode: CGKeyCode) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let names: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 10: "ISO Section", 11: "B", 12: "Q", 13: "W", 14: "E",
        15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Backspace", 53: "Escape", 54: "Right ⌘", 55: "Left ⌘",
        58: "Left ⌥", 59: "Left ⌃", 61: "Right ⌥", 62: "Right ⌃",
        64: "F17", 65: "Keypad Decimal", 67: "Keypad *", 69: "Keypad +",
        71: "Keypad Clear", 75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -",
        79: "F18", 80: "F19", 81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1",
        84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 90: "F20", 91: "Keypad 8", 92: "Keypad 9",
        93: "JIS Yen", 94: "JIS Underscore", 95: "JIS Keypad Comma", 96: "F5",
        97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 102: "JIS Eisu",
        103: "F11", 104: "JIS Kana", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home",
        116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "Left Arrow", 124: "Right Arrow",
        125: "Down Arrow", 126: "Up Arrow",
    ]
}
