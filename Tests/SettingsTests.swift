import Foundation
import TwoCmdCore

// Standalone persistence tests. The default-source closure isolates the OS lookup.
private var failures = 0

private func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("  ok   — \(message)")
    } else {
        failures += 1
        print("  FAIL — \(message) (line \(line))")
    }
}

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let domain = "dev.anton.2cmd.settings-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    try body(defaults)
}

@main
private enum SettingsTests {
    static func main() throws {
        print("Binding settings")
        withDefaults { defaults in
            let settings = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
            expect(
                settings.bindings == [
                    KeyBinding(keyCode: 55, sourceID: "default.en"),
                    KeyBinding(keyCode: 54, sourceID: "default.ru"),
                ], "new installation uses the existing English and Russian default rules")
            expect(settings.isEnabled, "new installation is enabled")
        }
        try withDefaults { defaults in
            let settings = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
            let chosen = [
                KeyBinding(keyCode: 0, sourceID: "unknown.variant"),
                KeyBinding(keyCode: 62, sourceID: "unknown.variant"),
                KeyBinding(keyCode: 53, sourceID: "third"),
            ]
            try settings.apply(chosen)
            settings.isEnabled = false
            let restarted = Settings(defaults: defaults, defaultSourceID: { _ in "replacement" })
            expect(
                restarted.bindings == chosen,
                "ordered keys and repeated unknown source IDs survive restart")
            expect(!restarted.isEnabled, "Enabled survives restart independently")
            try restarted.apply(Array(chosen.prefix(2)))
            let withoutOptional = Settings(
                defaults: defaults, defaultSourceID: { _ in "replacement" })
            expect(
                withoutOptional.bindings == Array(chosen.prefix(2)),
                "removed optional rows are not reseeded")
        }
        try withDefaults { defaults in
            let settings = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
            let valid = [
                KeyBinding(keyCode: 55, sourceID: "one"),
                KeyBinding(keyCode: 54, sourceID: "two"),
            ]
            try settings.apply(valid)
            let invalid: [([KeyBinding], BindingValidationError)] = [
                ([], .count),
                ([valid[0]], .count),
                (Array(repeating: valid[0], count: 6), .count),
                ([valid[0], KeyBinding(keyCode: nil, sourceID: "two")], .missingKey(1)),
                ([valid[0], KeyBinding(keyCode: 57, sourceID: "two")], .unsupportedKey(1)),
                ([valid[0], KeyBinding(keyCode: 63, sourceID: "two")], .unsupportedKey(1)),
                ([valid[0], KeyBinding(keyCode: 72, sourceID: "two")], .unsupportedKey(1)),
                ([valid[0], KeyBinding(keyCode: 56, sourceID: "two")], .unsupportedKey(1)),
                ([valid[0], valid[0]], .duplicateKey(1, 0)),
                ([valid[0], KeyBinding(keyCode: 54, sourceID: nil)], .missingSource(1)),
                ([valid[0], KeyBinding(keyCode: 54, sourceID: "")], .missingSource(1)),
            ]
            for (draft, error) in invalid {
                do {
                    try settings.apply(draft)
                    expect(false, "invalid configuration rejects \(error)")
                } catch let actual as BindingValidationError {
                    expect(actual == error, "invalid configuration rejects \(error)")
                }
                expect(
                    settings.bindings == valid, "rejected Apply leaves committed bindings unchanged"
                )
                let restarted = Settings(defaults: defaults, defaultSourceID: { _ in nil })
                expect(
                    restarted.bindings == valid,
                    "rejected Apply leaves persisted bindings unchanged")
            }
            let five =
                valid + [
                    KeyBinding(keyCode: 0, sourceID: "one"),
                    KeyBinding(keyCode: 59, sourceID: "one"),
                    KeyBinding(keyCode: 122, sourceID: "one"),
                ]
            try settings.apply(five)
            expect(
                settings.bindings == five,
                "five unique supported keys with repeated sources can be applied")
        }
        withDefaults { defaults in
            defaults.set("legacy.unavailable", forKey: "leftSourceID")
            defaults.set("legacy.variant", forKey: "rightSourceID")
            defaults.set(false, forKey: "enabled")
            let settings = Settings(defaults: defaults, defaultSourceID: { _ in "replacement" })
            let migrated = [
                KeyBinding(keyCode: 55, sourceID: "legacy.unavailable"),
                KeyBinding(keyCode: 54, sourceID: "legacy.variant"),
            ]
            expect(
                settings.bindings == migrated, "migration preserves exact legacy input-source IDs")
            expect(!settings.isEnabled, "migration preserves Enabled")
            let restarted = Settings(defaults: defaults, defaultSourceID: { _ in nil })
            expect(
                restarted.bindings == migrated,
                "migrated configuration survives restart without default lookup")
        }
        withDefaults { defaults in
            defaults.set("retained", forKey: "leftSourceID")
            let settings = Settings(defaults: defaults, defaultSourceID: { _ in nil })
            expect(
                settings.bindings == [
                    KeyBinding(keyCode: 55, sourceID: "retained"),
                    KeyBinding(keyCode: 54, sourceID: nil),
                ], "missing OS default remains an unconfigured mandatory row")
            let restarted = Settings(defaults: defaults, defaultSourceID: { _ in "new.default" })
            expect(
                restarted.bindings == settings.bindings,
                "unconfigured initial rows are not silently reseeded")
            settings.setSourceID("selected", at: 1)
            let updated = Settings(defaults: defaults, defaultSourceID: { _ in nil })
            expect(
                updated.bindings[1].sourceID == "selected",
                "quick source selection saves immediately")
        }
        withDefaults { defaults in
            defaults.set("", forKey: "leftSourceID")
            defaults.set("retained", forKey: "rightSourceID")
            let settings = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
            expect(
                settings.bindings == [
                    KeyBinding(keyCode: 55, sourceID: "default.en"),
                    KeyBinding(keyCode: 54, sourceID: "retained"),
                ], "empty legacy selections use the existing missing-selection default rule")
        }
        withDefaults { defaults in
            let settings = Settings(defaults: defaults, defaultSourceID: { _ in nil })
            settings.setSourceID("selected", at: 0)
            let restarted = Settings(defaults: defaults, defaultSourceID: { _ in "replacement" })
            expect(restarted.loadError == nil, "partially configured initial rows remain loadable")
            expect(
                restarted.bindings == [
                    KeyBinding(keyCode: 55, sourceID: "selected"),
                    KeyBinding(keyCode: 54, sourceID: nil),
                ], "quick selection preserves another unconfigured mandatory row")
        }
        for malformed: Any in [
            "not Codable data",
            Data("{broken".utf8),
            Data("[]".utf8),
            Data(
                "[{\"keyCode\":55,\"sourceID\":\"one\"},{\"keyCode\":55,\"sourceID\":\"two\"}]".utf8
            ),
            Data(
                "[{\"keyCode\":57,\"sourceID\":\"one\"},{\"keyCode\":54,\"sourceID\":\"two\"}]".utf8
            ),
            Data(
                "[{\"keyCode\":55,\"sourceID\":\"one\"},{\"keyCode\":54,\"sourceID\":\"two\"},{\"keyCode\":0}]"
                    .utf8),
        ] {
            try withDefaults { defaults in
                defaults.set(malformed, forKey: "bindings")
                let settings = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
                expect(
                    settings.loadError != nil,
                    "malformed saved configuration exposes a recovery error")
                expect(
                    settings.bindings == [
                        KeyBinding(keyCode: 55, sourceID: "default.en"),
                        KeyBinding(keyCode: 54, sourceID: "default.ru"),
                    ], "malformed saved configuration supplies usable initial rows")
                settings.setSourceID("silent.overwrite", at: 0)
                let restarted = Settings(defaults: defaults, defaultSourceID: { "default.\($0)" })
                expect(
                    restarted.loadError != nil,
                    "load and quick selection do not overwrite malformed user data")
                try settings.apply([
                    KeyBinding(keyCode: 0, sourceID: "recovered"),
                    KeyBinding(keyCode: 54, sourceID: "two"),
                ])
                let recovered = Settings(defaults: defaults, defaultSourceID: { _ in nil })
                expect(
                    recovered.loadError == nil,
                    "explicit valid Apply replaces malformed configuration")
                expect(
                    recovered.bindings == settings.bindings, "explicit recovery survives restart")
            }
        }
        if failures > 0 { exit(1) }
        print("All settings tests passed.")
    }
}
