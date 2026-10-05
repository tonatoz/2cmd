import AppKit
import CoreGraphics
import TwoCmdCore

/// Adapts physical keyboard events to configured input-source bindings.
///
/// Uses `.defaultTap` rather than `.listenOnly` on purpose: since macOS 10.15 a
/// listen-only keyboard tap is gated by the separate Input Monitoring service
/// (`kTCCServiceListenEvent`), whereas `.defaultTap` is covered by the Accessibility
/// grant this app already asks for. One permission instead of two.
///
/// Main thread only: the tap's run loop source is attached to the main run loop, so
/// the C callback fires on the main thread.
final class KeyTapMonitor {
    var onSelectSource: ((String) -> Void)?
    var onRecordedKey: ((CGKeyCode) -> Void)?

    var bindings: [KeyBinding] = [] {
        didSet { configureDetector() }
    }

    var isEnabled = false {
        didSet { configureDetector() }
    }

    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            generation &+= 1
            detector.setRecording(isRecording)
        }
    }

    private(set) var isRunning = false

    private var detector = KeyBindingDetector(enabled: false)
    private var generation: UInt64 = 0
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseMonitors: [Any] = []

    /// Creates and installs the event tap. Returns `false` if the tap could not be
    /// created (normally: Accessibility permission missing).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    if let refcon,
                        Unmanaged<KeyTapMonitor>.fromOpaque(refcon)
                            .takeUnretainedValue()
                            .handle(type: type, event: event)
                    {
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        // Keep observing when disabled to pair releases of already-suppressed keys.
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        isRunning = true
        installMouseMonitors()
        return true
    }

    // MARK: - Event handling

    private func configureDetector() {
        generation &+= 1
        detector.configure(bindings: bindings, enabled: isEnabled)
    }

    /// Returns whether this event belongs to an intercepted press.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            detector.recoverFromInterruption(
                physicalFnIsHeld: CGEventSource.keyState(.hidSystemState, key: 63))
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let decision = detector.handle(
            type: type,
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        let currentGeneration = generation
        if let sourceID = decision.sourceID {
            // Text Input Sources must not run inside the event-tap callback.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration,
                    self.isEnabled, !self.isRecording
                else { return }
                self.onSelectSource?(sourceID)
            }
        }
        if let keyCode = decision.recordedKeyCode {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration, self.isRecording else {
                    return
                }
                self.onRecordedKey?(keyCode)
            }
        }
        return decision.suppress
    }

    /// Mouse and scroll events cancel a pending tap (so ⌘-click behaves normally).
    /// `NSEvent` monitors are used rather than the tap itself — including mouse
    /// events in a `CGEventTap` is known to interfere with dragging.
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] _ in
                self?.detector.cancel()
            })
        {
            mouseMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.detector.cancel()
                return event
            })
        {
            mouseMonitors.append(local)
        }
    }
}
