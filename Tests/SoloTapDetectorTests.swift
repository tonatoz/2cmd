import CoreGraphics

// Self-contained test runner for the solo-tap state machine.
//
// It is deliberately not an XCTest/swift-testing target: neither framework ships
// with the Command Line Tools, and this project is built without full Xcode.
// Compiled together with Sources/TwoCmdCore/SoloTapDetector.swift — see `make test`.

/// Cumulative device-dependent modifier bits, as reported by the event tap.
private enum Flag {
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftShift: UInt64 = 0x0000_0002
    static let leftOption: UInt64 = 0x0000_0020
    static let capsLock: UInt64 = 0x0001_0000
    static let none: UInt64 = 0
}

private enum Key {
    static let leftCommand: CGKeyCode = 55
    static let rightCommand: CGKeyCode = 54
    static let leftShift: CGKeyCode = 56
    static let capsLock: CGKeyCode = 57
    static let leftOption: CGKeyCode = 58
    static let a: CGKeyCode = 0
}

private var failures = 0

private func expect(
    _ actual: CommandSide?,
    _ expected: CommandSide?,
    _ what: String,
    line: Int = #line
) {
    if actual == expected {
        print("  ok   — \(what)")
    } else {
        failures += 1
        print(
            "  FAIL — \(what): expected \(String(describing: expected)), got \(String(describing: actual)) (line \(line))"
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
enum SoloTapDetectorTests {
    static func main() {
        print("Solo ⌘ tap detection")

        // A bare tap of either ⌘ is the whole point of the app.
        do {
            var detector = SoloTapDetector()
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand), nil,
                "left ⌘ down alone does not fire yet")
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), .left,
                "left ⌘ tap fires left")
        }

        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.rightCommand, flags: Flag.rightCommand)
            expect(
                detector.modifierChanged(keyCode: Key.rightCommand, flags: Flag.none), .right,
                "right ⌘ tap fires right")
        }

        // ⌘C: the tap sees a keyDown, which voids the gesture.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.cancel()
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), nil,
                "⌘C does not fire")
        }

        // ⌘-click: the mouse monitor voids the gesture.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.cancel()
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), nil,
                "⌘-click does not fire")
        }

        // ⌘⇧: the second modifier takes over candidacy, so neither release fires.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            _ = detector.modifierChanged(
                keyCode: Key.leftShift, flags: Flag.leftCommand | Flag.leftShift)
            expect(
                detector.modifierChanged(keyCode: Key.leftShift, flags: Flag.leftCommand), nil,
                "⌘⇧ — releasing ⇧ does not fire")
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), nil,
                "⌘⇧ — releasing ⌘ afterwards does not fire")
        }

        // Other modifiers tapped alone must stay inert.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftShift, flags: Flag.leftShift)
            expect(
                detector.modifierChanged(keyCode: Key.leftShift, flags: Flag.none), nil,
                "⇧ tap alone does not fire")
            _ = detector.modifierChanged(keyCode: Key.capsLock, flags: Flag.capsLock)
            expect(
                detector.modifierChanged(keyCode: Key.capsLock, flags: Flag.none), nil,
                "caps lock tap does not fire")
        }

        // Both ⌘ held: device-dependent bits keep press/release attribution exact.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            _ = detector.modifierChanged(
                keyCode: Key.rightCommand, flags: Flag.leftCommand | Flag.rightCommand)
            expect(
                detector.modifierChanged(keyCode: Key.rightCommand, flags: Flag.leftCommand), nil,
                "releasing right ⌘ while left ⌘ is held does not fire")
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), nil,
                "releasing left ⌘ afterwards does not fire")
        }

        // ⌥⌘ released ⌥-first: ⌘ is still the candidate, but ⌥ was held meanwhile.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftOption, flags: Flag.leftOption)
            _ = detector.modifierChanged(
                keyCode: Key.leftCommand, flags: Flag.leftOption | Flag.leftCommand)
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftOption), nil,
                "⌥⌘ — releasing ⌘ while ⌥ is held does not fire")
        }

        // Caps lock is latched, not held: it must not block ⌘ taps.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(
                keyCode: Key.leftCommand, flags: Flag.capsLock | Flag.leftCommand)
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.capsLock), .left,
                "left ⌘ tap still fires while caps lock is on")
        }

        // A non-modifier key code arriving as flagsChanged must not be mistaken for ⌘.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            expect(
                detector.modifierChanged(keyCode: Key.a, flags: Flag.leftCommand), nil,
                "unknown key code does not fire")
            expect(
                detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none), nil,
                "unknown key code voids the pending gesture")
        }

        // A voided gesture must not wedge the detector.
        do {
            var detector = SoloTapDetector()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.leftCommand)
            detector.cancel()
            _ = detector.modifierChanged(keyCode: Key.leftCommand, flags: Flag.none)
            _ = detector.modifierChanged(keyCode: Key.rightCommand, flags: Flag.rightCommand)
            expect(
                detector.modifierChanged(keyCode: Key.rightCommand, flags: Flag.none), .right,
                "detector still works after a voided gesture")
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
