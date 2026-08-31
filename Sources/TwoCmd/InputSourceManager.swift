import Carbon
import Foundation

/// A selectable keyboard layout / input method known to the system.
struct InputSource: Equatable {
    let id: String
    let name: String
    let languages: [String]

    var primaryLanguage: String? { languages.first }
}

/// Thin wrapper over Text Input Source Services (TIS).
///
/// All calls must happen on the main thread — `TISSelectInputSource` is not
/// documented as thread safe and the whole app is main-thread only anyway.
enum InputSourceManager {
    /// Enabled, selectable keyboard input sources in system order.
    static func availableSources() -> [InputSource] {
        sources(matching: nil).compactMap(makeInputSource)
    }

    /// Selects the layout with the given input source ID. Returns `false` when the
    /// layout is unknown (e.g. the user removed it in System Settings).
    @discardableResult
    static func select(id: String) -> Bool {
        guard let source = sources(matching: [kTISPropertyInputSourceID as String: id]).first else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    /// Best guess default for a language code such as `"en"` or `"ru"`:
    /// an already-enabled layout for that language, otherwise whatever the system
    /// suggests via `TISCopyInputSourceForLanguage`.
    static func defaultSourceID(forLanguage language: String) -> String? {
        if let enabled = availableSources().first(where: { $0.primaryLanguage == language }) {
            return enabled.id
        }
        guard let suggested = TISCopyInputSourceForLanguage(language as CFString)?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(suggested, kTISPropertyInputSourceID)
    }

    static func name(forID id: String, in sources: [InputSource]) -> String? {
        sources.first { $0.id == id }?.name
    }

    // MARK: - Private

    private static func sources(matching filter: [String: Any]?) -> [TISInputSource] {
        let cfFilter = filter.map { $0 as CFDictionary }
        guard let list = TISCreateInputSourceList(cfFilter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    private static func makeInputSource(_ source: TISInputSource) -> InputSource? {
        guard isSelectableKeyboardSource(source),
              let id = stringProperty(source, kTISPropertyInputSourceID),
              let name = stringProperty(source, kTISPropertyLocalizedName)
        else { return nil }
        return InputSource(id: id, name: name, languages: languages(source))
    }

    private static func isSelectableKeyboardSource(_ source: TISInputSource) -> Bool {
        guard let category = stringProperty(source, kTISPropertyInputSourceCategory),
              category == (kTISCategoryKeyboardInputSource as String)
        else { return false }
        return boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
            && boolProperty(source, kTISPropertyInputSourceIsEnabled)
    }

    private static func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
