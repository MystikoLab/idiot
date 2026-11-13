import Foundation

nonisolated struct PendingQuickLog: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var amount: Double
    var categoryID: UUID
    var categoryName: String
    var type: String
    var date: Date
}

nonisolated enum QuickLogQueue {
    static let appGroupID = "group.com.umangsurana.idiot"
    static let key = "pendingQuickLogs"
    static let changeNotification = "com.umangsurana.idiot.quicklog"

    static func load() -> [PendingQuickLog] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([PendingQuickLog].self, from: data)
        else {
            return []
        }
        return entries
    }

    static func append(_ entry: PendingQuickLog) {
        store(load() + [entry])
    }

    static func remove(ids: Set<UUID>) {
        store(load().filter { !ids.contains($0.id) })
    }

    static func notifyApp() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changeNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private static func store(_ entries: [PendingQuickLog]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
