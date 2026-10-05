import AppKit
import ApplicationServices
import Carbon
import TwoCmdCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let monitor = KeyTapMonitor()
    private var statusItem: StatusItemController?
    private var activationTimer: Timer?
    private var activation: ActivationCoordinator?

    init(settings: Settings = Settings()) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onBindingsChanged = { [weak self] in
            self?.refreshBindings()
        }

        let statusItem = StatusItemController(settings: settings)
        statusItem.onEnabledChanged = { [weak self] isEnabled in
            self?.monitor.isEnabled = isEnabled
        }
        self.statusItem = statusItem

        monitor.onSelectSource = { [weak self] id in
            guard let self else { return }
            let selected = InputSourceManager.select(id: id)
            Log.tap.info("select \(id, privacy: .public) -> \(selected, privacy: .public)")
            if !selected { self.refreshBindings() }
        }
        monitor.onRecordedKey = { [weak statusItem] keyCode in
            statusItem?.receiveRecordedKey(keyCode)
        }
        statusItem.onRecordingChanged = { [weak self] recording in
            self?.monitor.isRecording = recording
        }
        monitor.isEnabled = settings.isEnabled
        refreshBindings()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourcesChanged(_:)),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )

        startActivation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Private

    private func refreshBindings() {
        let availableIDs = Set(InputSourceManager.availableSources().map(\.id))
        monitor.bindings = settings.bindings.filter { binding in
            guard let id = binding.sourceID else { return false }
            return availableIDs.contains(id)
        }
    }

    @objc private func inputSourcesChanged(_ notification: Notification) {
        refreshBindings()
    }

    /// A `CGEventTap` needs the Accessibility permission, which can only be observed
    /// by asking. Prompt once, then keep polling: the permission may be granted (or
    /// revoked and re-granted) at any time, and the tap may fail independently.
    private func startActivation() {
        var activation = ActivationCoordinator(
            isTrusted: { AXIsProcessTrusted() },
            startTap: { [monitor] in monitor.start() }
        )

        let promptedTrust = isProcessTrustedWithPrompt()
        Log.permissions.info("launch: AXIsProcessTrusted=\(promptedTrust, privacy: .public)")

        let finished = activation.advance()
        self.activation = activation
        report(activation.state)
        guard !finished else { return }

        activationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard let self, var activation = self.activation else { return }
            let previous = activation.state
            let finished = activation.advance()
            self.activation = activation
            if activation.state != previous {
                self.report(activation.state)
            }
            if finished {
                timer.invalidate()
                self.activationTimer = nil
            }
        }
    }

    private func report(_ state: ActivationState) {
        Log.tap.info("activation state: \(String(describing: state), privacy: .public)")
        statusItem?.activationState = state
        statusItem?.canRecordKeys = state == .running && AXIsProcessTrusted()
    }

    private func isProcessTrustedWithPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
