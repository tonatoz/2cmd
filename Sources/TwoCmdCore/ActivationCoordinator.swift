/// What is standing between the app and a working key tap.
public enum ActivationState: Equatable, Sendable {
    /// macOS does not trust this process for Accessibility yet.
    case waitingForPermission
    /// Accessibility is granted, but the event tap could not be created.
    case tapCreationFailed
    /// The tap is up and running.
    case running
}

/// Drives startup: waits for the Accessibility permission, then creates the tap,
/// retrying until it actually succeeds.
///
/// Retrying matters because the two failure modes are independent — a granted
/// permission does not guarantee `tapCreate` succeeds — and because giving up would
/// leave the app permanently dead until the user relaunches it.
public struct ActivationCoordinator {
    private let isTrusted: () -> Bool
    private let startTap: () -> Bool

    public private(set) var state: ActivationState = .waitingForPermission

    public init(isTrusted: @escaping () -> Bool, startTap: @escaping () -> Bool) {
        self.isTrusted = isTrusted
        self.startTap = startTap
    }

    /// Performs one attempt. Returns `true` once the tap runs and polling can stop.
    @discardableResult
    public mutating func advance() -> Bool {
        if state == .running { return true }

        guard isTrusted() else {
            state = .waitingForPermission
            return false
        }

        if startTap() {
            state = .running
            return true
        }

        state = .tapCreationFailed
        return false
    }
}
