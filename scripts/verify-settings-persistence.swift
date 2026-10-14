import Foundation
import IslandCore

@main
struct VerifySettingsPersistence {
    static func main() throws {
        let domain = "com.dan.dynomite.verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var original = Preferences()
        original.features[.powerDisconnected] = FeaturePreference(duration: 7)
        original.features[.volume] = FeaturePreference(duration: 2)
        original.normalize()
        defaults.set(try JSONEncoder().encode(original), forKey: "preferences.v1")
        let older = SettingsStore(defaults: defaults)
        let newer = SettingsStore(defaults: UserDefaults(suiteName: domain)!)
        newer.setDuration(.powerDisconnected, 4)
        newer.setDuration(.volume, 10)
        newer.flush()
        older.flush()
        let saved = try JSONDecoder().decode(Preferences.self, from: defaults.data(forKey: "preferences.v1")!)
        precondition(saved.preference(for: .powerDisconnected).duration == 4, "Unchanged older process reset the duration")
        older.setEnabled(.volume, false)
        older.flush()
        let relaunched = SettingsStore(defaults: UserDefaults(suiteName: domain)!)
        precondition(relaunched.preferences.preference(for: .powerDisconnected).duration == 4)
        precondition(relaunched.preferences.preference(for: .volume).duration == 10, "Toggle reset a concurrently updated duration")
        precondition(!relaunched.preferences.preference(for: .volume).enabled)
        relaunched.preferences.keepOfflineVisible = true
        relaunched.preferences.internetProbeAddress = "8.8.8.8"
        relaunched.flush()
        let updated = SettingsStore(defaults: UserDefaults(suiteName: domain)!)
        precondition(updated.preferences.keepOfflineVisible && updated.preferences.internetProbeAddress == "8.8.8.8")
        print("Settings persistence: relaunch, custom durations, unchanged older process, concurrent toggle/duration edits and new internet settings passed")
    }
}
