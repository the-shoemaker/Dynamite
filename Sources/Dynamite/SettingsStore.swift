import AppKit
import Combine
import IslandCore

final class SettingsStore: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }
    private var saveWork: DispatchWorkItem?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        saved.normalize()
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
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences.v1") }
    }
    func setDuration(_ feature: Feature, _ duration: Double) {
        var pref = preferences.preference(for: feature)
        pref.duration = ActivityDuration.validated(duration)
        preferences.features[feature] = pref
    }
}
