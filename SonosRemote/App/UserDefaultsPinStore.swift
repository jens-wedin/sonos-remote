import Foundation
import SonosKit

/// Persists speaker key pins under one UserDefaults key so a relaunch keeps trusting the same keys.
struct UserDefaultsPinStore: TrustPinStore {
    static let key = "speakerKeyPins"
    /// UserDefaults is documented as thread-safe; the compiler can't see that, and this store is
    /// called from the URLSession delegate queue.
    nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [String: Data] {
        defaults.dictionary(forKey: Self.key)?.compactMapValues { $0 as? Data } ?? [:]
    }

    func save(_ pins: [String: Data]) {
        defaults.set(pins, forKey: Self.key)
    }
}
