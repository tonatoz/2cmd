import CoreGraphics

/// The observable result of one physical keyboard or gesture event.
public struct BindingDecision {
    public var sourceID: String?
    public var suppress: Bool
    public var recordedKeyCode: CGKeyCode?

    public init(
        sourceID: String? = nil, suppress: Bool = false, recordedKeyCode: CGKeyCode? = nil
    ) {
        self.sourceID = sourceID
        self.suppress = suppress
        self.recordedKeyCode = recordedKeyCode
    }
}

/// Recognizes configured physical-key presses without changing modifier shortcuts.
public struct KeyBindingDetector {
    private var bindings: [KeyBinding]
    private var enabled: Bool
    private var recording = false
    private var recordingHasCapture = false
    private var pendingKeyCode: CGKeyCode?
    private var suppressedKeys = PhysicalKeySet()
    private var pressedModifiers = PhysicalKeySet()
    private var suppressedModifiers = PhysicalKeySet()

    public init(bindings: [KeyBinding] = [], enabled: Bool = true) {
        self.bindings = bindings
        self.enabled = enabled
    }

    public mutating func configure(bindings: [KeyBinding], enabled: Bool) {
        self.bindings = bindings
        self.enabled = enabled
        cancel()
    }

    public mutating func setRecording(_ recording: Bool) {
        self.recording = recording
        recordingHasCapture = false
        cancel()
    }

    public mutating func handle(
        type: CGEventType, keyCode: CGKeyCode, flags: UInt64, isRepeat: Bool = false
    ) -> BindingDecision {
        guard keyCode < 128 else {
            cancel()
            return BindingDecision()
        }
        if type == .keyDown {
            cancel()
            if isRepeat {
                return BindingDecision(suppress: suppressedKeys.contains(keyCode))
            }
            // A non-repeat down starts a fresh press, even if Secure Event Input hid its predecessor's up.
            suppressedKeys.remove(keyCode)
            if recording, !recordingHasCapture {
                recordingHasCapture = true
                suppressedKeys.insert(keyCode)
                return BindingDecision(suppress: true, recordedKeyCode: keyCode)
            }
            let intrinsicFunctionFlag: UInt64 =
                KeyboardKey.hasIntrinsicFunctionFlag(keyCode)
                ? CGEventFlags.maskSecondaryFn.rawValue : 0
            guard enabled, !recording,
                flags & (KeyboardKey.heldModifierMask & ~intrinsicFunctionFlag) == 0,
                !pressedModifiers.contains(63),
                KeyboardKey.isAssignable(keyCode), !KeyboardKey.isModifier(keyCode),
                let sourceID = sourceID(for: keyCode)
            else {
                return BindingDecision()
            }
            suppressedKeys.insert(keyCode)
            return BindingDecision(sourceID: sourceID, suppress: true)
        }
        if type == .keyUp {
            cancel()
            let suppress = suppressedKeys.contains(keyCode)
            suppressedKeys.remove(keyCode)
            return BindingDecision(suppress: suppress)
        }
        guard type == .flagsChanged else {
            cancel()
            return BindingDecision()
        }
        // Caps Lock reports a latched toggle, not a held modifier bit. Either
        // direction is a candidate while recording; it never starts a solo tap.
        if keyCode == 57 {
            cancel()
            if suppressedModifiers.contains(keyCode) {
                suppressedModifiers.remove(keyCode)
                return BindingDecision(suppress: true)
            }
            if recording, !recordingHasCapture {
                recordingHasCapture = true
                suppressedModifiers.insert(keyCode)
                return BindingDecision(suppress: true, recordedKeyCode: keyCode)
            }
            return BindingDecision()
        }
        guard let flag = Self.modifierFlag(for: keyCode) else {
            cancel()
            return BindingDecision()
        }
        if flags & flag != 0 {
            let otherHeld =
                flags & KeyboardKey.heldModifierMask
                & ~(flag | Self.genericModifierFlag(for: keyCode))
            if pressedModifiers.contains(keyCode) {
                if otherHeld != 0 { cancel() }
                return BindingDecision(suppress: suppressedModifiers.contains(keyCode))
            }
            pressedModifiers.insert(keyCode)
            suppressedModifiers.remove(keyCode)
            cancel()
            if recording, !recordingHasCapture {
                recordingHasCapture = true
                suppressedModifiers.insert(keyCode)
                return BindingDecision(suppress: true, recordedKeyCode: keyCode)
            }
            pendingKeyCode =
                enabled && !recording && KeyboardKey.isModifier(keyCode)
                    && otherHeld == 0
                ? keyCode : nil
            return BindingDecision()
        }
        pressedModifiers.remove(keyCode)
        let wasSolo = pendingKeyCode == keyCode
        cancel()
        if suppressedModifiers.contains(keyCode) {
            suppressedModifiers.remove(keyCode)
            return BindingDecision(suppress: true)
        }
        guard wasSolo, flags & KeyboardKey.heldModifierMask == 0 else {
            return BindingDecision()
        }
        return BindingDecision(sourceID: sourceID(for: keyCode))
    }

    /// Cancels solo-modifier candidacy without changing a press's event pairing.
    public mutating func cancel() {
        pendingKeyCode = nil
    }

    /// Re-enable after an event-stream gap without stranding passed-key state.
    /// Intercepted presses retain suppression until their matching release.
    public mutating func recoverFromInterruption(physicalFnIsHeld: Bool = false) {
        pressedModifiers = suppressedModifiers
        if physicalFnIsHeld {
            pressedModifiers.insert(63)
        } else {
            pressedModifiers.remove(63)
        }
        cancel()
    }

    private func sourceID(for keyCode: CGKeyCode) -> String? {
        bindings.first { $0.keyCode == keyCode }?.sourceID
    }

    private static func modifierFlag(for keyCode: CGKeyCode) -> UInt64? {
        switch keyCode {
        case 56: return 0x02
        case 60: return 0x04
        case 63: return CGEventFlags.maskSecondaryFn.rawValue
        default: return KeyboardKey.modifierFlags[keyCode]
        }
    }

    private static func genericModifierFlag(for keyCode: CGKeyCode) -> UInt64 {
        switch keyCode {
        case 54, 55: return CGEventFlags.maskCommand.rawValue
        case 58, 61: return CGEventFlags.maskAlternate.rawValue
        case 59, 62: return CGEventFlags.maskControl.rawValue
        case 56, 60: return CGEventFlags.maskShift.rawValue
        case 63: return CGEventFlags.maskSecondaryFn.rawValue
        default: return 0
        }
    }
}

/// macOS physical virtual key codes occupy two words, without per-event allocation.
private struct PhysicalKeySet {
    private var low: UInt64 = 0
    private var high: UInt64 = 0

    func contains(_ keyCode: CGKeyCode) -> Bool {
        guard keyCode < 128 else { return false }
        let bit = UInt64(1) << (keyCode & 63)
        return (keyCode < 64 ? low : high) & bit != 0
    }

    mutating func insert(_ keyCode: CGKeyCode) {
        guard keyCode < 128 else { return }
        let bit = UInt64(1) << (keyCode & 63)
        if keyCode < 64 {
            low |= bit
        } else {
            high |= bit
        }
    }

    mutating func remove(_ keyCode: CGKeyCode) {
        guard keyCode < 128 else { return }
        let bit = UInt64(1) << (keyCode & 63)
        if keyCode < 64 {
            low &= ~bit
        } else {
            high &= ~bit
        }
    }
}
