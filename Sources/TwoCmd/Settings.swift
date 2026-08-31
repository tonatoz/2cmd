import Foundation
import TwoCmdCore

/// Persisted preferences (UserDefaults).
final class Settings {
    private enum Key {
        static let enabled = "enabled"
        static let leftSourceID = "leftSourceID"
        static let rightSourceID = "rightSourceID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.enabled: true])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    func sourceID(for side: CommandSide) -> String? {
        let value = defaults.string(forKey: key(for: side))
        return (value?.isEmpty ?? true) ? nil : value
    }

    func setSourceID(_ id: String, for side: CommandSide) {
        defaults.set(id, forKey: key(for: side))
    }

    /// First launch: left ⌘ → English layout, right ⌘ → Russian layout,
    /// picked from the layouts the user already has enabled.
    func seedDefaultsIfNeeded() {
        let languages: [CommandSide: String] = [.left: "en", .right: "ru"]
        for side in CommandSide.allCases {
            guard sourceID(for: side) == nil, let language = languages[side] else { continue }
            if let id = InputSourceManager.defaultSourceID(forLanguage: language) {
                setSourceID(id, for: side)
            }
        }
    }

    private func key(for side: CommandSide) -> String {
        switch side {
        case .left: return Key.leftSourceID
        case .right: return Key.rightSourceID
        }
    }
}
