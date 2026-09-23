import Foundation

public enum PreferencesMigration {
    public static func migrate(from legacy: UserDefaults, to current: UserDefaults) {
        let marker = "preferences.legacyMigrationCompleted"
        guard !current.bool(forKey: marker) else { return }
        for key in ["monitor.settings", "NSWindow Frame LinkSentinel.MainWindow"] {
            if current.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
        current.set(true, forKey: marker)
    }
}
