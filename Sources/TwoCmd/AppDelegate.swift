import AppKit
import ApplicationServices
import TwoCmdCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let monitor = KeyTapMonitor()
    private var statusItem: StatusItemController?
    private var activationTimer: Timer?
    private var activation: ActivationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.seedDefaultsIfNeeded()

        let statusItem = StatusItemController(settings: settings)
        statusItem.onEnabledChanged = { [weak self] isEnabled in
            self?.monitor.isEnabled = isEnabled
        }
        self.statusItem = statusItem

        monitor.onSoloTap = { [weak self] side in
            self?.selectLayout(for: side)
        }
        monitor.isEnabled = settings.isEnabled

        startActivation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationTimer?.invalidate()
    }

    // MARK: - Private

    private func selectLayout(for side: CommandSide) {
        guard let id = settings.sourceID(for: side) else {
            Log.tap.error("no layout configured for \(String(describing: side), privacy: .public)")
            return
        }
        let selected = InputSourceManager.select(id: id)
        Log.tap.info("select \(id, privacy: .public) -> \(selected, privacy: .public)")
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

        activationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
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
    }

    private func isProcessTrustedWithPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
