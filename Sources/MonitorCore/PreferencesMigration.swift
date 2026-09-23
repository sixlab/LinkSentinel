import Foundation

public enum PreferencesMigration {
    public static func migrate(from legacy: UserDefaults, to current: UserDefaults) {
        let marker = "preferences.legacyMigrationCompleted"
        if !current.bool(forKey: marker) {
            for key in ["monitor.settings", "NSWindow Frame LinkSentinel.MainWindow"] {
                if current.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                    current.set(value, forKey: key)
                }
            }
            current.set(true, forKey: marker)
        }

        let urlMarker = "preferences.headProbeDefaultURLMigrated"
        guard !current.bool(forKey: urlMarker) else { return }
        if let data = current.data(forKey: "monitor.settings"),
           var settings = try? JSONDecoder().decode(MonitorSettings.self, from: data),
           ["https://www.google.com", "https://www.google.com/"].contains(settings.url.absoluteString) {
            settings.url = MonitorSettings.defaults.url
            guard let updated = try? JSONEncoder().encode(settings) else { return }
            current.set(updated, forKey: "monitor.settings")
        }
        current.set(true, forKey: urlMarker)
    }
}
