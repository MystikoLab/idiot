import Foundation
import Observation

@Observable
final class OpeningBalance {
    static let key = "startingAmount"
    static let shared = OpeningBalance()

    static var amount: Double {
        shared.value
    }

    static func set(_ value: Double) {
        shared.update(value, pushToCloud: true)
    }

    static func start() {
        shared.startSyncing()
    }

    private(set) var value: Double
    @ObservationIgnored private var isSyncing = false

    private init() {
        value = UserDefaults.standard.double(forKey: Self.key)
    }

    private func startSyncing() {
        guard !isSyncing else { return }
        isSyncing = true
        let store = NSUbiquitousKeyValueStore.default
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.pullFromCloud()
        }
        store.synchronize()
        if store.object(forKey: Self.key) == nil {
            if value != 0 {
                store.set(value, forKey: Self.key)
            }
        } else {
            pullFromCloud()
        }
    }

    private func pullFromCloud() {
        let store = NSUbiquitousKeyValueStore.default
        guard store.object(forKey: Self.key) != nil else { return }
        update(store.double(forKey: Self.key), pushToCloud: false)
    }

    private func update(_ newValue: Double, pushToCloud: Bool) {
        if value != newValue {
            value = newValue
        }
        UserDefaults.standard.set(newValue, forKey: Self.key)
        UserDefaults(suiteName: WidgetStore.appGroupID)?.set(newValue, forKey: Self.key)
        if pushToCloud {
            NSUbiquitousKeyValueStore.default.set(newValue, forKey: Self.key)
        }
    }
}
