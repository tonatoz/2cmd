import AppKit
import Carbon
import CoreGraphics
import TwoCmdCore

/// Owns one editable draft. Settings remains the only persistent store.
final class BindingConfigurationController: NSObject, NSWindowDelegate {
    var onRecordingChanged: ((Bool) -> Void)?
    var recordingAvailable = false {
        didSet {
            guard recordingAvailable != oldValue else { return }
            if !recordingAvailable { stopRecording() }
            if isOpen { render() }
        }
    }
    private(set) var isOpen = false

    private let settings: Settings
    private var window: NSWindow?
    private var contentStack: NSStackView?
    private var draft: [KeyBinding] = []
    private var recordingRow: Int?
    private var message: String?

    init(settings: Settings) {
        self.settings = settings
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourcesChanged(_:)),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func show() {
        if !isOpen {
            stopRecording()
            isOpen = true
            draft = settings.bindings
            message = nil
            if window == nil { createWindow() }
            render()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func receiveRecordedKey(_ keyCode: CGKeyCode) {
        guard let index = recordingRow, draft.indices.contains(index) else { return }
        stopRecording()
        if !KeyboardKey.isAssignable(keyCode) {
            message =
                "This key is not supported. Fn/Globe, Caps Lock, Shift, and multimedia keys cannot be assigned."
        } else if let conflict = draft.indices.first(where: {
            $0 != index && draft[$0].keyCode == keyCode
        }) {
            message =
                "\(KeyboardKey.name(for: keyCode)) is already assigned to row \(conflict + 1). Edit that row or record another key."
        } else {
            draft[index].keyCode = keyCode
            message = nil
        }
        render()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        draft = []
        isOpen = false
        message = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        render()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard recordingRow != nil else { return }
        stopRecording()
        message = "Key recording stopped because the configuration window lost focus."
        render()
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Configure Key Bindings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        self.window = window
        contentStack = stack
    }

    private func render() {
        guard let stack = contentStack, !draft.isEmpty else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let sources = InputSourceManager.availableSources()
        addLabel(
            "Assign physical keys to input sources. The first two rows are required. Add up to three optional rows.",
            to: stack)
        addLabel(
            "Command, Option, Control, character, function, navigation, and editing keys are supported. Fn/Globe, Caps Lock, Shift, and multimedia keys are not.",
            to: stack, color: .secondaryLabelColor)
        if let error = settings.loadError { addLabel(error, to: stack, color: .systemRed) }
        if !recordingAvailable {
            addLabel(
                "Key recording is unavailable. Enable Accessibility access and make sure 2cmd is running.",
                to: stack, color: .systemOrange)
        }
        for (index, binding) in draft.enumerated() {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4
            let controls = NSStackView()
            controls.orientation = .horizontal
            controls.spacing = 8
            let number = NSTextField(labelWithString: "\(index + 1).")
            number.widthAnchor.constraint(equalToConstant: 20).isActive = true
            controls.addArrangedSubview(number)
            let key = NSTextField(
                labelWithString: binding.keyCode.map(KeyboardKey.name(for:)) ?? "No key selected")
            key.lineBreakMode = .byTruncatingTail
            key.widthAnchor.constraint(equalToConstant: 155).isActive = true
            key.setAccessibilityLabel("Row \(index + 1) key")
            controls.addArrangedSubview(key)

            let source = NSPopUpButton(frame: .zero, pullsDown: false)
            source.tag = index
            source.target = self
            source.action = #selector(sourceChanged(_:))
            source.setAccessibilityLabel("Row \(index + 1) input source")
            source.widthAnchor.constraint(equalToConstant: 320).isActive = true
            source.isEnabled = recordingRow == nil
            source.addItem(withTitle: "Choose input source…")
            source.lastItem?.isEnabled = false
            for available in sources {
                // addItem(withTitle:) can merge duplicate display names. Preserve IDs separately.
                let item = NSMenuItem(title: available.name, action: nil, keyEquivalent: "")
                item.representedObject = available.id
                source.menu?.addItem(item)
            }
            if let id = binding.sourceID {
                if let item = source.itemArray.first(where: {
                    $0.representedObject as? String == id
                }) {
                    source.select(item)
                } else {
                    let item = NSMenuItem(
                        title: "Unavailable: \(id)", action: nil, keyEquivalent: "")
                    item.representedObject = id
                    source.menu?.addItem(item)
                    source.select(item)
                }
            } else {
                source.selectItem(at: 0)
            }
            controls.addArrangedSubview(source)
            let record = button(
                recordingRow == index ? "Cancel Recording" : "Record Key",
                action: #selector(recordKey(_:)))
            record.tag = index
            record.widthAnchor.constraint(equalToConstant: 135).isActive = true
            record.isEnabled = recordingAvailable || recordingRow == index
            controls.addArrangedSubview(record)
            if index >= BindingConfiguration.requiredCount {
                let remove = button("Delete", action: #selector(deleteRow(_:)))
                remove.tag = index
                remove.widthAnchor.constraint(equalToConstant: 75).isActive = true
                remove.isEnabled = recordingRow == nil
                controls.addArrangedSubview(remove)
            } else {
                let required = NSTextField(labelWithString: "Required")
                required.textColor = .secondaryLabelColor
                required.widthAnchor.constraint(equalToConstant: 75).isActive = true
                controls.addArrangedSubview(required)
            }
            row.addArrangedSubview(controls)
            var warnings: [String] = []
            if let keyCode = binding.keyCode, !KeyboardKey.isModifier(keyCode) {
                warnings.append(
                    "This key’s ordinary action is suppressed while this binding is active.")
            }
            if let id = binding.sourceID, !sources.contains(where: { $0.id == id }) {
                warnings.append(
                    "Input source unavailable. This key keeps its ordinary action until the source returns."
                )
            }
            if recordingRow == index {
                warnings.append(
                    "Press one key. Escape can be assigned. Use Cancel Recording to stop.")
            }
            if !warnings.isEmpty {
                addLabel(warnings.joined(separator: "\n"), to: row, color: .systemOrange)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if let message {
            addLabel(message, to: stack, color: .systemRed)
        } else if let error = BindingConfiguration.validationError(in: draft) {
            addLabel(Self.validationMessage(error), to: stack, color: .systemRed)
        }
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        let add = button("Add Binding", action: #selector(addRow(_:)))
        add.isEnabled = recordingRow == nil && draft.count < BindingConfiguration.maximumCount
        actions.addArrangedSubview(add)
        let reset = button("Restore Standard Keys", action: #selector(restoreStandardKeys(_:)))
        reset.isEnabled = recordingRow == nil
        actions.addArrangedSubview(reset)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)
        actions.addArrangedSubview(button("Cancel", action: #selector(cancel(_:))))
        let apply = button("Apply", action: #selector(apply(_:)))
        apply.keyEquivalent = "\r"
        apply.isEnabled =
            recordingRow == nil && BindingConfiguration.validationError(in: draft) == nil
        actions.addArrangedSubview(apply)
        stack.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        window?.contentView?.layoutSubtreeIfNeeded()
        if let window {
            let size = NSSize(width: 840, height: max(260, stack.fittingSize.height + 40))
            let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            var frame = window.frame
            frame.origin.y += frame.height - newFrame.height
            frame.size = newFrame.size
            window.setFrame(frame, display: true)
        }
    }

    private func addLabel(_ text: String, to stack: NSStackView, color: NSColor = .labelColor) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = color
        label.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func stopRecording() {
        guard recordingRow != nil else { return }
        recordingRow = nil
        onRecordingChanged?(false)
    }

    @objc private func recordKey(_ sender: NSButton) {
        if recordingRow == sender.tag {
            stopRecording()
        } else if recordingAvailable {
            stopRecording()
            recordingRow = sender.tag
            onRecordingChanged?(true)
        }
        message = nil
        render()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        guard draft.indices.contains(sender.tag),
            let id = sender.selectedItem?.representedObject as? String
        else { return }
        draft[sender.tag].sourceID = id
        message = nil
        render()
    }

    @objc private func addRow(_ sender: NSButton) {
        guard draft.count < BindingConfiguration.maximumCount else { return }
        stopRecording()
        draft.append(KeyBinding(keyCode: nil, sourceID: nil))
        message = nil
        render()
    }

    @objc private func deleteRow(_ sender: NSButton) {
        guard sender.tag >= BindingConfiguration.requiredCount, draft.indices.contains(sender.tag)
        else {
            return
        }
        stopRecording()
        draft.remove(at: sender.tag)
        message = nil
        render()
    }

    @objc private func restoreStandardKeys(_ sender: NSButton) {
        stopRecording()
        draft = BindingConfiguration.standard(
            leftSourceID: draft[0].sourceID, rightSourceID: draft[1].sourceID)
        message = nil
        render()
    }

    @objc private func apply(_ sender: NSButton) {
        stopRecording()
        do {
            try settings.apply(draft)
            window?.close()
        } catch let error as BindingValidationError {
            message = Self.validationMessage(error)
            render()
        } catch {
            message = "Could not save bindings: \(error.localizedDescription)"
            render()
        }
    }

    @objc private func cancel(_ sender: NSButton) {
        stopRecording()
        window?.close()
    }

    @objc private func inputSourcesChanged(_ notification: Notification) {
        if isOpen { render() }
    }

    private static func validationMessage(_ error: BindingValidationError) -> String {
        switch error {
        case .count:
            return "Configure between two and five bindings."
        case .missingKey(let index):
            return "Record a key for row \(index + 1) before applying."
        case .unsupportedKey(let index):
            return "Row \(index + 1) uses an unsupported key. Record a supported key."
        case .duplicateKey(let index, let existing):
            return
                "Row \(index + 1) uses the same key as row \(existing + 1). Record a different key."
        case .missingSource(let index):
            return "Select an input source for row \(index + 1) before applying."
        }
    }
}
