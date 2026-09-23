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
}
