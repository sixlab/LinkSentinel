import XCTest
@testable import MonitorCore

final class PreferencesMigrationTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults, UserDefaults) throws -> Void) rethrows {
        let oldName = "LinkSentinelTests.legacy.\(UUID().uuidString)"
        let newName = "LinkSentinelTests.current.\(UUID().uuidString)"
        let old = UserDefaults(suiteName: oldName)!
        let current = UserDefaults(suiteName: newName)!
        defer {
            old.removePersistentDomain(forName: oldName)
            current.removePersistentDomain(forName: newName)
        }
        try test(old, current)
    }

    func testPreservesLegacySettingsAndWindowPosition() throws {
        try withDefaults { old, current in
            let settings = MonitorSettings(url: URL(string: "https://example.com/health")!, thresholdMilliseconds: 1500, intervalSeconds: 8)
            let saved = try JSONEncoder().encode(settings)
            old.set(saved, forKey: "monitor.settings")
            old.set("100 200 960 680 0 0 1920 1080 ", forKey: "NSWindow Frame LinkSentinel.MainWindow")
            PreferencesMigration.migrate(from: old, to: current)
            let restored = try JSONDecoder().decode(MonitorSettings.self, from: XCTUnwrap(current.data(forKey: "monitor.settings")))
            XCTAssertEqual(restored, settings)
            XCTAssertEqual(current.string(forKey: "NSWindow Frame LinkSentinel.MainWindow"), old.string(forKey: "NSWindow Frame LinkSentinel.MainWindow"))
            XCTAssertEqual(old.data(forKey: "monitor.settings"), saved)
        }
    }

    func testDoesNotOverwriteCurrentPreferences() {
        withDefaults { old, current in
            old.set(Data("old".utf8), forKey: "monitor.settings")
            current.set(Data("new".utf8), forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            XCTAssertEqual(current.data(forKey: "monitor.settings"), Data("new".utf8))
        }
    }

    func testMigrationDoesNotRunAgainAfterUserRemovesSettings() {
        withDefaults { old, current in
            old.set(Data("old".utf8), forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            current.removeObject(forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            XCTAssertNil(current.object(forKey: "monitor.settings"))
            XCTAssertTrue(current.bool(forKey: "preferences.legacyMigrationCompleted"))
        }
    }

    func testOldDefaultURLUpgradesEvenAfterLegacyMigrationCompleted() throws {
        for url in ["https://www.google.com", "https://www.google.com/"] {
            try withDefaults { old, current in
                let saved = MonitorSettings(url: URL(string: url)!, thresholdMilliseconds: 100, intervalSeconds: 7)
                current.set(try JSONEncoder().encode(saved), forKey: "monitor.settings")
                current.set(true, forKey: "preferences.legacyMigrationCompleted")
                PreferencesMigration.migrate(from: old, to: current)
                let restored = try JSONDecoder().decode(MonitorSettings.self, from: XCTUnwrap(current.data(forKey: "monitor.settings")))
                XCTAssertEqual(restored.url.absoluteString, "https://www.gstatic.com/generate_204")
                XCTAssertEqual(restored.thresholdMilliseconds, 100)
                XCTAssertEqual(restored.intervalSeconds, 7)
            }
        }
    }

    func testDefaultURLUpgradePreservesCustomGoogleURL() throws {
        try withDefaults { old, current in
            let saved = MonitorSettings(url: URL(string: "https://www.google.com/search?q=monitor")!, thresholdMilliseconds: 500, intervalSeconds: 8)
            current.set(try JSONEncoder().encode(saved), forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            let restored = try JSONDecoder().decode(MonitorSettings.self, from: XCTUnwrap(current.data(forKey: "monitor.settings")))
            XCTAssertEqual(restored, saved)
        }
    }

    func testDefaultURLUpgradeDoesNotOverrideLaterUserChoice() throws {
        try withDefaults { old, current in
            let saved = MonitorSettings(url: URL(string: "https://www.google.com")!, thresholdMilliseconds: 600, intervalSeconds: 9)
            current.set(try JSONEncoder().encode(saved), forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            let upgraded = try JSONDecoder().decode(MonitorSettings.self, from: XCTUnwrap(current.data(forKey: "monitor.settings")))
            XCTAssertEqual(upgraded.url.absoluteString, "https://www.gstatic.com/generate_204")
            current.set(try JSONEncoder().encode(saved), forKey: "monitor.settings")
            PreferencesMigration.migrate(from: old, to: current)
            let restored = try JSONDecoder().decode(MonitorSettings.self, from: XCTUnwrap(current.data(forKey: "monitor.settings")))
            XCTAssertEqual(restored, saved)
        }
    }
}
