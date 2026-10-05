import Foundation
import TwoCmdCore

/// Owns the ordered binding configuration and its UserDefaults persistence.
final class Settings {
    private enum Key {
        static let enabled = "enabled"
        static let bindings = "bindings"
        static let leftSourceID = "leftSourceID"
        static let rightSourceID = "rightSourceID"
    }

    private let defaults: UserDefaults
    private(set) var bindings: [KeyBinding]
    private(set) var loadError: String?
    var onBindingsChanged: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        defaultSourceID: (String) -> String? = InputSourceManager.defaultSourceID(forLanguage:)
    ) {
        self.defaults = defaults
        defaults.register(defaults: [Key.enabled: true])
        if defaults.object(forKey: Key.bindings) != nil {
            if let data = defaults.data(forKey: Key.bindings),
                let stored = try? JSONDecoder().decode([KeyBinding].self, from: data),
                BindingConfiguration.validationError(
                    in: stored, allowUnconfiguredRequiredRows: true) == nil
            {
                bindings = stored
                defaults.removeObject(forKey: Key.leftSourceID)
                defaults.removeObject(forKey: Key.rightSourceID)
                return
            }
            bindings = BindingConfiguration.standard(
                leftSourceID: defaultSourceID("en"), rightSourceID: defaultSourceID("ru"))
            loadError =
                "Saved bindings could not be loaded. They have not been overwritten. "
                + "Review these replacement rows and choose Apply to save them."
            return
        }
        let legacyLeft = defaults.string(forKey: Key.leftSourceID).flatMap { $0.isEmpty ? nil : $0 }
        let legacyRight = defaults.string(forKey: Key.rightSourceID).flatMap {
            $0.isEmpty ? nil : $0
        }
        bindings = BindingConfiguration.standard(
            leftSourceID: legacyLeft ?? defaultSourceID("en"),
            rightSourceID: legacyRight ?? defaultSourceID("ru"))
        do {
            try save(bindings)
        } catch {
            loadError = "Could not save the initial bindings: \(error.localizedDescription)"
        }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    func apply(_ bindings: [KeyBinding]) throws {
        if let error = BindingConfiguration.validationError(in: bindings) { throw error }
        try save(bindings)
        self.bindings = bindings
        loadError = nil
        onBindingsChanged?()
    }

    func setSourceID(_ id: String, at index: Int) {
        guard loadError == nil, bindings.indices.contains(index), !id.isEmpty else { return }
        var updated = bindings
        updated[index].sourceID = id
        do {
            try save(updated)
            bindings = updated
            onBindingsChanged?()
        } catch {
            loadError = "Could not save the selected input source: \(error.localizedDescription)"
        }
    }

    private func save(_ bindings: [KeyBinding]) throws {
        defaults.set(try JSONEncoder().encode(bindings), forKey: Key.bindings)
        defaults.removeObject(forKey: Key.leftSourceID)
        defaults.removeObject(forKey: Key.rightSourceID)
    }

}
