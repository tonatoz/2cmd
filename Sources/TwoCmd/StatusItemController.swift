import AppKit
import ServiceManagement
import TwoCmdCore

/// Menu bar icon plus its dropdown menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Ties a submenu item to the ⌘ side it configures.
    private final class SourceSelection: NSObject {
        let side: CommandSide
        let id: String

        init(side: CommandSide, id: String) {
            self.side = side
            self.id = id
        }
    }

    /// Called when the user flips the "enabled" checkbox.
    var onEnabledChanged: ((Bool) -> Void)?

    /// Kept in sync by the app delegate.
    var activationState: ActivationState = .waitingForPermission {
        didSet { refreshIcon() }
    }

    private let settings: Settings
    private let statusItem: NSStatusItem

    init(settings: Settings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let image = NSImage(systemSymbolName: "command", accessibilityDescription: "2cmd")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    /// Dims the icon when taps are off or the permission is missing.
    func refreshIcon() {
        statusItem.button?.appearsDisabled = !(settings.isEnabled && activationState == .running)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(
            checkboxItem(
                title: "Enabled",
                isOn: settings.isEnabled,
                action: #selector(toggleEnabled)
            ))

        switch activationState {
        case .running:
            break
        case .waitingForPermission:
            menu.addItem(.separator())
            menu.addItem(disabledItem(title: "No Accessibility permission"))
            // An ad-hoc signature pins the TCC grant to this exact build's cdhash, so
            // after a rebuild the old row stays switched on while access is denied.
            // Flipping that switch only rewrites the allow bit, not the stored code
            // requirement — the row has to be removed so macOS records the new build.
            menu.addItem(
                disabledItem(title: "Already enabled in Settings? Remove 2cmd from the list"))
            menu.addItem(
                disabledItem(
                    title: "with “−” and add it again — toggling it off and on will not help"))
            menu.addItem(
                actionItem(
                    title: "Open Accessibility Settings…",
                    action: #selector(openAccessibilitySettings)
                ))
            menu.addItem(actionItem(title: "Relaunch 2cmd", action: #selector(relaunch)))
        case .tapCreationFailed:
            menu.addItem(.separator())
            menu.addItem(disabledItem(title: "Permission granted, but the tap did not start"))
            menu.addItem(disabledItem(title: "Retrying every second"))
            menu.addItem(actionItem(title: "Relaunch 2cmd", action: #selector(relaunch)))
        }

        menu.addItem(.separator())
        let sources = InputSourceManager.availableSources()
        menu.addItem(layoutItem(title: "Left ⌘", side: .left, sources: sources))
        menu.addItem(layoutItem(title: "Right ⌘", side: .right, sources: sources))

        menu.addItem(.separator())
        menu.addItem(
            checkboxItem(
                title: "Launch at Login",
                isOn: SMAppService.mainApp.status == .enabled,
                action: #selector(toggleLaunchAtLogin)
            ))

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Check for Updates…", action: #selector(checkForUpdates)))

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func layoutItem(title: String, side: CommandSide, sources: [InputSource]) -> NSMenuItem
    {
        let selectedID = settings.sourceID(for: side)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let selectedID, let name = InputSourceManager.name(forID: selectedID, in: sources) {
            item.title = "\(title): \(name)"
        }

        let submenu = NSMenu()
        if sources.isEmpty {
            submenu.addItem(disabledItem(title: "No input sources available"))
        }
        for source in sources {
            let subitem = NSMenuItem(
                title: source.name, action: #selector(selectSource(_:)), keyEquivalent: "")
            subitem.target = self
            subitem.representedObject = SourceSelection(side: side, id: source.id)
            subitem.state = source.id == selectedID ? .on : .off
            submenu.addItem(subitem)
        }
        item.submenu = submenu
        return item
    }

    private func checkboxItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = actionItem(title: title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        onEnabledChanged?(settings.isEnabled)
        refreshIcon()
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? SourceSelection else { return }
        settings.setSourceID(selection.id, for: selection.side)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// `AXIsProcessTrusted()` can keep returning a stale value for the life of a
    /// process, so a relaunch is the reliable way to pick up a fresh grant.
    @objc private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release?):
                let alert = NSAlert()
                alert.messageText = "Version \(release.tag) is available"
                alert.informativeText =
                    "You are running \(UpdateChecker.currentVersion.map(Self.describe) ?? "an unknown version")."
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.pageURL)
                }
            case .success(nil):
                self.presentAlert(
                    title: "2cmd is up to date",
                    message: "No newer release was found.",
                    style: .informational
                )
            case .failure(let error):
                self.presentAlert(
                    title: "Could not check for updates",
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func describe(_ version: Version) -> String {
        version.components.map(String.init).joined(separator: ".")
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            presentAlert(
                title: "Could not change the login item",
                message:
                    "\(error.localizedDescription)\n\nLaunch at login only works for an app in /Applications."
            )
        }
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
