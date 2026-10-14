import AppKit
import Combine
import IslandCore

final class SettingsStore: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            saveWork?.cancel()
            saveWork = nil
            guard preferences != savedPreferences else { return }
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }
    private var saveWork: DispatchWorkItem?
    private let defaults: UserDefaults
    private var savedPreferences: Preferences
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        saved.normalize()
        savedPreferences = saved
        preferences = saved
    }
    func setEnabled(_ feature: Feature, _ enabled: Bool) {
        var pref = preferences.preference(for: feature)
        pref.enabled = enabled
        preferences.features[feature] = pref
    }
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        // An unchanged startup snapshot must never overwrite settings saved by
        // another running copy. Merge only actual edits, field by field.
        guard preferences != savedPreferences else { return }
        var latest = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? savedPreferences
        latest.normalize()
        let merged = Preferences.mergingChanges(from: savedPreferences, current: preferences, saved: latest)
        guard let data = try? JSONEncoder().encode(merged) else { return }
        defaults.set(data, forKey: "preferences.v1")
        savedPreferences = merged
        if preferences != merged { preferences = merged }
    }
    func setDuration(_ feature: Feature, _ duration: Double) {
        var pref = preferences.preference(for: feature)
        pref.duration = ActivityDuration.validated(duration)
        preferences.features[feature] = pref
    }
}
