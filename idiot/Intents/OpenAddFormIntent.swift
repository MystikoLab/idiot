import AppIntents
import Foundation

nonisolated enum AddFormRequest {
    static let appGroupID = "group.com.umangsurana.idiot"
    static let key = "pendingAddFormRequest"
    static let notification = Notification.Name("IdiotOpenAddFormRequest")

    static func post() {
        UserDefaults(suiteName: appGroupID)?.set(Date.now.timeIntervalSince1970, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func consume() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID), defaults.object(forKey: key) != nil else {
            return false
        }
        let stamp = defaults.double(forKey: key)
        defaults.removeObject(forKey: key)
        return abs(Date.now.timeIntervalSince1970 - stamp) < 120
    }
}

nonisolated struct OpenAddFormIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let description = IntentDescription("Opens Idiot on the new transaction form.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AddFormRequest.post()
        return .result()
    }
}
