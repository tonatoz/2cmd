import CoreGraphics

// Self-contained test runner for key-binding recognition.
//
// It is deliberately not an XCTest/swift-testing target: neither framework ships
// with the Command Line Tools, and this project is built without full Xcode.
// Compiled together with Sources/TwoCmdCore/*.swift — see `make test`.

/// Cumulative device-dependent modifier bits, as reported by the event tap.
private enum Flag {
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftShift: UInt64 = 0x0000_0002
    static let leftOption: UInt64 = 0x0000_0020
    static let rightOption: UInt64 = 0x0000_0040
    static let leftControl: UInt64 = 0x0000_0001
    static let rightControl: UInt64 = 0x0000_2000
    static let rightShift: UInt64 = 0x0000_0004
    static let fn: UInt64 = 0x0080_0000
    static let capsLock: UInt64 = 0x0001_0000
    static let none: UInt64 = 0
}

private enum Key {
    static let leftCommand: CGKeyCode = 55
    static let rightCommand: CGKeyCode = 54
    static let leftShift: CGKeyCode = 56
    static let capsLock: CGKeyCode = 57
    static let leftOption: CGKeyCode = 58
    static let rightOption: CGKeyCode = 61
    static let leftControl: CGKeyCode = 59
    static let rightControl: CGKeyCode = 62
    static let rightShift: CGKeyCode = 60
    static let fn: CGKeyCode = 63
    static let b: CGKeyCode = 11
    static let escape: CGKeyCode = 53
    static let a: CGKeyCode = 0
}

private var failures = 0

private func expect(
    _ actual: BindingDecision,
    sourceID: String? = nil,
    suppress: Bool = false,
    recordedKeyCode: CGKeyCode? = nil,
    _ what: String,
    line: Int = #line
) {
    if actual.sourceID == sourceID, actual.suppress == suppress,
        actual.recordedKeyCode == recordedKeyCode
    {
        print("  ok   — \(what)")
    } else {
        failures += 1
        print(
            "  FAIL — \(what): expected (source=\(String(describing: sourceID)), suppress=\(suppress), recorded=\(String(describing: recordedKeyCode))), got (source=\(String(describing: actual.sourceID)), suppress=\(actual.suppress), recorded=\(String(describing: actual.recordedKeyCode))) (line \(line))"
        )
    }
}

private func expectState(
    _ done: Bool,
    _ expectedDone: Bool,
    _ state: ActivationState,
    _ expectedState: ActivationState,
    _ what: String,
    line: Int = #line
) {
    if done == expectedDone, state == expectedState {
        print("  ok   — \(what)")
    } else {
        failures += 1
        print(
            "  FAIL — \(what): expected (done=\(expectedDone), \(expectedState)), got (done=\(done), \(state)) (line \(line))"
        )
    }
}

private func expectCount(_ actual: Int, _ expected: Int, _ what: String, line: Int = #line) {
    if actual == expected {
        print("  ok   — \(what)")
    } else {
        failures += 1
        print("  FAIL — \(what): expected \(expected), got \(actual) (line \(line))")
    }
}

@main
enum KeyBindingDetectorTests {
    static func main() {
        print("Key-binding recognition")

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.leftCommand, sourceID: "left"),
                KeyBinding(keyCode: Key.rightCommand, sourceID: "right"),
            ])
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand),
                "left Command press waits for release")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                sourceID: "left", "left Command solo release selects its source")
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.rightCommand, flags: Flag.rightCommand),
                "right Command press waits for release")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.rightCommand, flags: Flag.none),
                sourceID: "right", "right Command solo release selects its source")
        }

        let modifiers: [(CGKeyCode, UInt64, String)] = [
            (Key.leftCommand, Flag.leftCommand, "left Command"),
            (Key.rightCommand, Flag.rightCommand, "right Command"),
            (Key.leftOption, Flag.leftOption, "left Option"),
            (Key.rightOption, Flag.rightOption, "right Option"),
            (Key.leftControl, Flag.leftControl, "left Control"),
            (Key.rightControl, Flag.rightControl, "right Control"),
        ]
        for (key, flag, name) in modifiers {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: name)
            ])
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: flag | Flag.capsLock),
                "\(name) press passes with Caps Lock latched")
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: Flag.capsLock),
                sourceID: name, "\(name) solo release selects with Caps Lock latched")
        }

        for event: CGEventType in [
            .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .null,
        ] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.leftCommand, sourceID: "left")
            ])
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: event, keyCode: Key.b, flags: Flag.leftCommand),
                "activity passes while Command is held")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "keyboard, mouse, scrolling, and unknown activity cancel solo switching")
        }

        for (otherKey, otherFlag) in [
            (Key.rightCommand, Flag.rightCommand), (Key.leftShift, Flag.leftShift),
            (Key.rightShift, Flag.rightShift), (Key.leftOption, Flag.leftOption),
            (Key.rightOption, Flag.rightOption), (Key.leftControl, Flag.leftControl),
            (Key.rightControl, Flag.rightControl), (Key.fn, Flag.fn),
        ] {
            for releaseCommandFirst in [false, true] {
                var detector = KeyBindingDetector(bindings: [
                    KeyBinding(keyCode: Key.leftCommand, sourceID: "left"),
                    KeyBinding(keyCode: otherKey, sourceID: "other"),
                ])
                _ = detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
                _ = detector.handle(
                    type: .flagsChanged, keyCode: otherKey,
                    flags: Flag.leftCommand | otherFlag)
                let first = releaseCommandFirst ? Key.leftCommand : otherKey
                let second = releaseCommandFirst ? otherKey : Key.leftCommand
                let remaining = releaseCommandFirst ? otherFlag : Flag.leftCommand
                expect(
                    detector.handle(type: .flagsChanged, keyCode: first, flags: remaining),
                    "overlapping modifiers do not activate on the first release")
                expect(
                    detector.handle(type: .flagsChanged, keyCode: second, flags: Flag.none),
                    "overlapping modifiers do not activate on the final release")
            }
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.leftCommand, sourceID: "left")
            ])
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand,
                flags: Flag.leftCommand | Flag.leftOption)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "a modifier pressed while another is held cannot become a solo gesture")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.a, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "unknown modifier events cancel solo switching")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.cancel()
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "explicit gesture cancellation prevents switching")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                sourceID: "left", "a cancelled gesture does not prevent the next solo tap")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters")
            ])
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.capsLock),
                sourceID: "letters", suppress: true,
                "ordinary key switches on first key down despite latched Caps Lock")
            expect(
                detector.handle(
                    type: .keyDown, keyCode: Key.a, flags: Flag.capsLock, isRepeat: true),
                suppress: true, "ordinary auto-repeat stays suppressed without switching")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.b, flags: Flag.capsLock),
                "unrelated release passes")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.capsLock),
                suppress: true, "matching release stays suppressed")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                "unmatched release passes after the intercepted press ends")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                sourceID: "letters", suppress: true, "the next fresh press switches again")
            detector.cancel()
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "gesture cancellation keeps matching release suppression")
        }

        for heldFlag in [
            Flag.leftCommand, Flag.rightCommand, Flag.leftOption, Flag.rightOption,
            Flag.leftControl, Flag.rightControl, Flag.leftShift, Flag.rightShift, Flag.fn,
            CGEventFlags.maskCommand.rawValue, CGEventFlags.maskAlternate.rawValue,
            CGEventFlags.maskControl.rawValue, CGEventFlags.maskShift.rawValue,
            CGEventFlags.maskSecondaryFn.rawValue,
        ] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters")
            ])
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: heldFlag),
                "modifier-first ordinary shortcut passes without switching")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                "shortcut repeat passes even after the modifier is released")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                "shortcut release passes even after the modifier is released")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters"),
                KeyBinding(keyCode: Key.leftCommand, sourceID: "command"),
            ])
            _ = detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none)
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand),
                "a modifier pressed after a suppressed key still passes")
            expect(
                detector.handle(
                    type: .keyDown, keyCode: Key.a, flags: Flag.leftCommand, isRepeat: true),
                suppress: true, "later modifiers do not restore an intercepted ordinary press")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.leftCommand),
                suppress: true, "ordinary-first shortcut retains its matched suppressed release")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "a modifier overlapping an ordinary press cannot switch on release")
        }

        for key: CGKeyCode in [53, 76, 96, 117, 123, 126] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: "source")
            ])
            expect(
                detector.handle(type: .keyDown, keyCode: key, flags: Flag.none),
                sourceID: "source", suppress: true,
                "editing, keypad, function, and navigation assignments activate on key down")
            expect(
                detector.handle(type: .keyUp, keyCode: key, flags: Flag.none),
                suppress: true, "each supported ordinary category retains release suppression")
        }

        for key: CGKeyCode in [105, 123] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: "function")
            ])
            expect(
                detector.handle(type: .keyDown, keyCode: key, flags: Flag.fn),
                sourceID: "function", suppress: true,
                "intrinsic function flags do not block function and navigation bindings")
            expect(
                detector.handle(type: .keyUp, keyCode: key, flags: Flag.fn),
                suppress: true, "intrinsic function-key releases remain suppressed")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: 105, sourceID: "function")
            ])
            _ = detector.handle(type: .flagsChanged, keyCode: Key.fn, flags: Flag.fn)
            expect(
                detector.handle(type: .keyDown, keyCode: 105, flags: Flag.fn),
                "a physically held Fn still preserves its function-key combination")
            expect(
                detector.handle(type: .keyUp, keyCode: 105, flags: Flag.fn),
                "the physical Fn combination's release also passes")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.leftCommand, sourceID: "command")
            ])
            _ = detector.handle(type: .keyDown, keyCode: 48, flags: Flag.none)
            // Secure Event Input can hide Tab's release after focus enters a password field.
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                sourceID: "command", "a missed ordinary release does not wedge default Command taps"
            )
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters"),
                KeyBinding(keyCode: Key.leftCommand, sourceID: "command"),
            ])
            _ = detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none)
            _ = detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none)
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.recoverFromInterruption()
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                suppress: true, "tap recovery retains an intercepted ordinary repeat")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "tap recovery retains the intercepted release")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                sourceID: "command", "tap recovery discards stale passed modifier presses")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "old")
            ])
            _ = detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none)
            // The release is hidden, then the user changes the binding and presses again.
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.a, sourceID: "new")], enabled: true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                sourceID: "new", suppress: true,
                "a fresh non-repeat press after a lost release uses the current binding")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "the fresh recovered press retains its own release")
        }

        for (physicalFnIsHeld, expectedSource, expectedSuppression): (Bool, String?, Bool) in [
            (false, "function", true), (true, nil, false),
        ] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: 105, sourceID: "function")
            ])
            _ = detector.handle(type: .flagsChanged, keyCode: Key.fn, flags: Flag.fn)
            detector.recoverFromInterruption(physicalFnIsHeld: physicalFnIsHeld)
            expect(
                detector.handle(type: .keyDown, keyCode: 105, flags: Flag.fn),
                sourceID: expectedSource, suppress: expectedSuppression,
                "tap recovery reconciles physical Fn before interpreting intrinsic function flags")
        }

        for change in 0..<3 {
            let bindings = [KeyBinding(keyCode: Key.a, sourceID: "old")]
            var detector = KeyBindingDetector(bindings: bindings)
            _ = detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none)
            let nextBindings =
                change == 0 ? [] : [KeyBinding(keyCode: Key.a, sourceID: "new")]
            detector.configure(bindings: nextBindings, enabled: change != 1)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                suppress: true,
                "removal, disabling, or reconfiguration keeps an intercepted repeat suppressed")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.b, flags: Flag.none),
                "configuration changes do not suppress unrelated releases")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "configuration changes retain the intercepted release decision")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                sourceID: change == 2 ? "new" : nil, suppress: change == 2,
                "the next fresh press uses the new effective configuration")
        }

        for initiallyEnabled in [false, true] {
            var detector = KeyBindingDetector(
                bindings: initiallyEnabled ? [] : [KeyBinding(keyCode: Key.a, sourceID: "source")],
                enabled: initiallyEnabled)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                "disabled or unavailable bindings pass fresh ordinary presses")
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.a, sourceID: "source")], enabled: true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                "enabling or restoring availability cannot consume its repeats")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                "enabling or restoring availability cannot consume its matching release")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                sourceID: "source", suppress: true,
                "enabling or restoring availability activates the next fresh press")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.leftCommand, sourceID: "old")
            ])
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.leftCommand, sourceID: "new")], enabled: true)
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand),
                "configuration changes do not restart a held modifier gesture")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "configuration changes invalidate the pending modifier activation")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                sourceID: "new", "the next fresh modifier gesture uses the new binding")
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.leftCommand, sourceID: "new")], enabled: false)
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.leftCommand, sourceID: "new")], enabled: true)
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "mid-press enabling does not activate a passed modifier gesture")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "source")
            ])
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                "an orphan auto-repeat never starts an intercepted press")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                "an orphan auto-repeat retains an unsuppressed release")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.escape, sourceID: "escape"),
                KeyBinding(keyCode: Key.leftCommand, sourceID: "command"),
            ])
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.escape, flags: Flag.none),
                suppress: true, recordedKeyCode: Key.escape,
                "recording captures Escape instead of activating or cancelling")
            expect(
                detector.handle(
                    type: .keyDown, keyCode: Key.escape, flags: Flag.none, isRepeat: true),
                suppress: true, "recording does not repeatedly capture an auto-repeating key")
            detector.setRecording(false)
            expect(
                detector.handle(
                    type: .keyDown, keyCode: Key.escape, flags: Flag.none, isRepeat: true),
                suppress: true, "ending recording retains captured-key repeat suppression")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.escape, flags: Flag.none),
                suppress: true, "ending recording retains the captured key's release")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.escape, flags: Flag.none),
                sourceID: "escape", suppress: true,
                "the next press restores committed behavior after recording")
        }

        for (key, flag, name) in modifiers + [
            (Key.leftShift, Flag.leftShift, "left Shift"),
            (Key.rightShift, Flag.rightShift, "right Shift"),
            (Key.fn, Flag.fn, "Fn"),
        ] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: "source")
            ])
            detector.setRecording(true)
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: flag),
                suppress: true, recordedKeyCode: key,
                "recording captures \(name), including candidates the UI must reject")
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: flag),
                suppress: true, "a held recorded modifier does not produce another capture")
            detector.setRecording(false)
            detector.configure(
                bindings: [KeyBinding(keyCode: key, sourceID: "new")], enabled: false)
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: Flag.none),
                suppress: true,
                "ending recording and disabling retain the recorded modifier's release")
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: flag),
                "fresh disabled modifier presses pass after recording")
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: Flag.none),
                "fresh disabled modifier releases pass after recording")
        }

        do {
            var detector = KeyBindingDetector(
                bindings: [KeyBinding(keyCode: Key.a, sourceID: "source")], enabled: false)
            detector.setRecording(true)
            detector.configure(bindings: [], enabled: false)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none),
                suppress: true, recordedKeyCode: Key.a,
                "recording still captures after configure disables switching")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "disabled recording consumes the matching release")
            expect(
                detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none),
                "recording captures only the first fresh press in a session")
            _ = detector.handle(type: .keyUp, keyCode: Key.b, flags: Flag.none)
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none),
                suppress: true, recordedKeyCode: Key.b,
                "explicitly rearming recording captures another fresh key")
        }

        for initialCapsLockFlag in [Flag.capsLock, Flag.none] {
            var detector = KeyBindingDetector()
            detector.setRecording(true)
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.capsLock, flags: initialCapsLockFlag),
                suppress: true, recordedKeyCode: Key.capsLock,
                "Caps Lock is recorded for rejection whether the latched state turns on or off")
            detector.setRecording(false)
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.capsLock, flags: initialCapsLockFlag),
                suppress: true, "the recorded Caps Lock release remains consumed")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters"),
                KeyBinding(keyCode: Key.leftCommand, sourceID: "command"),
            ])
            _ = detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none)
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none, isRepeat: true),
                "starting recording does not consume an already-passed ordinary repeat")
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand),
                "starting recording does not capture an already-held modifier")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.b, flags: Flag.none),
                "starting recording retains an already-passed ordinary release")
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                "starting recording invalidates a pending modifier gesture")
            expect(
                detector.handle(
                    type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.leftCommand),
                suppress: true, recordedKeyCode: Key.leftCommand,
                "the next fresh modifier press can be recorded")
            detector.setRecording(false)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftCommand, flags: Flag.none),
                suppress: true, "a recorded modifier never activates on release")
        }

        do {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: Key.a, sourceID: "letters")
            ])
            _ = detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none)
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                suppress: true, "starting recording keeps an already-intercepted repeat suppressed")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                suppress: true, "starting recording keeps an already-intercepted release suppressed"
            )
            expect(
                detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.leftCommand),
                suppress: true, recordedKeyCode: Key.b,
                "recording captures fresh ordinary keys even with a modifier held")
        }

        do {
            var detector = KeyBindingDetector()
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.leftOption)
            detector.configure(
                bindings: [KeyBinding(keyCode: Key.leftOption, sourceID: "available")],
                enabled: true)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.none),
                "restoring availability does not activate an already-started modifier press")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.leftOption)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.none),
                sourceID: "available", "restored modifier bindings activate on the next solo tap")
            _ = detector.handle(
                type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.leftOption)
            detector.configure(bindings: [], enabled: true)
            expect(
                detector.handle(type: .flagsChanged, keyCode: Key.leftOption, flags: Flag.none),
                "losing availability cancels a pending modifier activation")
        }

        do {
            var detector = KeyBindingDetector()
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.a, flags: Flag.none, isRepeat: true),
                "recording ignores an orphan auto-repeat")
            expect(
                detector.handle(type: .keyUp, keyCode: Key.a, flags: Flag.none),
                "recording passes the orphan auto-repeat's release")
            detector.setRecording(false)
            expect(
                detector.handle(type: .keyDown, keyCode: Key.b, flags: Flag.none),
                "cancelling recording before a capture leaves the next press unchanged")
        }

        for key: CGKeyCode in [128, .max] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: "unsupported")
            ])
            detector.setRecording(true)
            expect(
                detector.handle(type: .keyDown, keyCode: key, flags: Flag.none),
                "out-of-range key codes pass without becoming recording candidates")
            expect(
                detector.handle(type: .keyDown, keyCode: key, flags: Flag.none, isRepeat: true),
                "out-of-range repeated events pass")
            expect(
                detector.handle(type: .keyUp, keyCode: key, flags: Flag.none),
                "out-of-range releases pass")
        }

        for (key, flag) in [
            (Key.leftShift, Flag.leftShift), (Key.rightShift, Flag.rightShift),
            (Key.fn, Flag.fn), (Key.capsLock, Flag.capsLock),
        ] {
            var detector = KeyBindingDetector(bindings: [
                KeyBinding(keyCode: key, sourceID: "unsupported")
            ])
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: flag),
                "unsupported modifiers cannot activate an injected assignment")
            expect(
                detector.handle(type: .flagsChanged, keyCode: key, flags: Flag.none),
                "unsupported modifier releases cannot activate an injected assignment")
        }

        print("\nActivation")

        // Untrusted: must keep waiting and must not touch the tap at all.
        do {
            var tapAttempts = 0
            var coordinator = ActivationCoordinator(
                isTrusted: { false },
                startTap: {
                    tapAttempts += 1
                    return true
                }
            )
            expectState(
                coordinator.advance(), false, coordinator.state, .waitingForPermission,
                "untrusted keeps waiting")
            expectCount(tapAttempts, 0, "untrusted does not attempt tapCreate")
        }

        // Trusted and tap creates: running, polling stops.
        do {
            var coordinator = ActivationCoordinator(isTrusted: { true }, startTap: { true })
            expectState(
                coordinator.advance(), true, coordinator.state, .running,
                "trusted + tap OK starts running")
        }

        // Trusted but tapCreate fails: distinct state, and polling must NOT stop —
        // this is the case the first implementation got wrong (gave up forever).
        do {
            var succeed = false
            var coordinator = ActivationCoordinator(isTrusted: { true }, startTap: { succeed })
            expectState(
                coordinator.advance(), false, coordinator.state, .tapCreationFailed,
                "trusted + tap failure reports tapCreationFailed")
            expectState(
                coordinator.advance(), false, coordinator.state, .tapCreationFailed,
                "tap failure keeps retrying")
            succeed = true
            expectState(
                coordinator.advance(), true, coordinator.state, .running,
                "retry succeeds once the tap can be created")
        }

        // Permission granted late, as when the user flips the checkbox while running.
        do {
            var trusted = false
            var coordinator = ActivationCoordinator(isTrusted: { trusted }, startTap: { true })
            _ = coordinator.advance()
            trusted = true
            expectState(
                coordinator.advance(), true, coordinator.state, .running,
                "late permission grant is picked up without restart")
        }

        // Once running, no further tap creation attempts.
        do {
            var tapAttempts = 0
            var coordinator = ActivationCoordinator(
                isTrusted: { true },
                startTap: {
                    tapAttempts += 1
                    return true
                }
            )
            _ = coordinator.advance()
            _ = coordinator.advance()
            expectCount(tapAttempts, 1, "running state does not re-create the tap")
        }

        print("\nVersion comparison")

        func expectTrue(_ actual: Bool, _ what: String, line: Int = #line) {
            if actual {
                print("  ok   — \(what)")
            } else {
                failures += 1
                print("  FAIL — \(what) (line \(line))")
            }
        }

        // Numeric per component: a string comparison would put 1.9 above 1.10.
        expectTrue(Version("1.10")! > Version("1.9")!, "1.10 is newer than 1.9")
        expectTrue(Version("2.0")! > Version("1.99.99")!, "2.0 is newer than 1.99.99")
        expectTrue(Version("1.2.3")! > Version("1.2")!, "1.2.3 is newer than 1.2")

        // Missing components count as zero.
        expectTrue(Version("1.2")! == Version("1.2.0")!, "1.2 equals 1.2.0")
        expectTrue(!(Version("1.0")! > Version("1.0")!), "equal versions are not newer")

        // Release tags carry a leading v.
        expectTrue(Version("v1.3")! == Version("1.3")!, "leading v is ignored")
        expectTrue(Version("v2.0")! > Version("v1.0")!, "tags compare like versions")

        // Pre-release suffixes read as their numeric prefix.
        expectTrue(Version("1.2.3-beta.1")! == Version("1.2.3")!, "pre-release suffix is ignored")

        // Junk must be rejected rather than silently parsed as zero.
        expectTrue(Version("main") == nil, "non-numeric string is rejected")
        expectTrue(Version("") == nil, "empty string is rejected")
        expectTrue(Version("v") == nil, "bare v is rejected")

        // The app must not offer an update when the running build is newer.
        expectTrue(
            !(Version("1.0")! > Version("1.1")!), "older release is not treated as an update")

        if failures == 0 {
            print("\nAll checks passed.")
        } else {
            print("\n\(failures) check(s) failed.")
            exit(1)
        }
    }
}
