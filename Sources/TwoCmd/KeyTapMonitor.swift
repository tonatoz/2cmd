import AppKit
import CoreGraphics
import TwoCmdCore

/// Watches the keyboard for a solo ⌘ tap via a `CGEventTap`. Every event is returned
/// unchanged — nothing is modified or swallowed.
///
/// Uses `.defaultTap` rather than `.listenOnly` on purpose: since macOS 10.15 a
/// listen-only keyboard tap is gated by the separate Input Monitoring service
/// (`kTCCServiceListenEvent`), whereas `.defaultTap` is covered by the Accessibility
/// grant this app already asks for. One permission instead of two.
///
/// Main thread only: the tap's run loop source is attached to the main run loop, so
/// the C callback fires on the main thread.
final class KeyTapMonitor {
    /// Called on the main thread when a solo ⌘ tap completes.
    var onSoloTap: ((CommandSide) -> Void)?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            detector.cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: isEnabled) }
        }
    }

    private(set) var isRunning = false

    private var detector = SoloTapDetector()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseMonitors: [Any] = []

    /// Creates and installs the event tap. Returns `false` if the tap could not be
    /// created (normally: Accessibility permission missing).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<KeyTapMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                        .handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: isEnabled)

        self.tap = tap
        runLoopSource = source
        isRunning = true
        installMouseMonitors()
        return true
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system can disable a tap on its own; bring it back up.
            detector.cancel()
            if let tap, isEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard let side = detector.modifierChanged(keyCode: keyCode, flags: event.flags.rawValue) else {
                return
            }
            Log.tap.info("solo tap: \(String(describing: side), privacy: .public)")
            // Hop out of the tap callback before touching Text Input Sources.
            DispatchQueue.main.async { [weak self] in
                self?.onSoloTap?(side)
            }
        default:
            // A real key was pressed while ⌘ was held: not a solo tap any more.
            detector.cancel()
        }
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

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.detector.cancel()
        }) {
            mouseMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.detector.cancel()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }
}
