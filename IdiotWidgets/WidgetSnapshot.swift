import SwiftUI
import WidgetKit

struct SnapshotRow: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var amount: Double
    var isIncome: Bool
    var date: Date
    var colorHex: String
    var iconName: String
}

struct SnapshotGoal: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var saved: Double
    var target: Double
    var status: String
    var deadline: Date?
    var colorHex: String
    var iconName: String
}

extension SnapshotGoal {
    var fraction: Double {
        target > 0 ? min(max(saved / target, 0), 1) : 0
    }

    var percent: Int {
        Int((fraction * 100).rounded(.down))
    }

    var isReached: Bool {
        status == "reached"
    }

    var statusLabel: String {
        switch status {
        case "reached": "Reached"
        case "onTrack": "On track"
        case "behind": "Behind"
        default: "In progress"
        }
    }

    var tint: Color {
        isReached ? .green : Color(snapshotHex: colorHex)
    }
}

struct SnapshotCategorySpend: Codable, Hashable {
    var id: UUID?
    var name: String
    var amount: Double
    var colorHex: String
}

struct SnapshotFrequent: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var amount: Double
    var categoryID: UUID
    var categoryName: String
    var colorHex: String
    var iconName: String
    var type: String
}

extension SnapshotFrequent {
    var isIncome: Bool {
        type == "income"
    }
}

struct SnapshotLogged: Codable, Hashable {
    var itemID: String
    var date: Date
}

struct WidgetSnapshot: Codable, Hashable {
    var monthLabel: String = ""
    var monthStart: Date?
    var income: Double = 0
    var expense: Double = 0
    var net: Double = 0
    var balance: Double = 0
    var overLimitCount: Int = 0
    var topCategoryName: String?
    var topCategoryAmount: Double = 0
    var rows: [SnapshotRow] = []
    var goals: [SnapshotGoal]?
    var categorySpend: [SnapshotCategorySpend]?
    var frequent: [SnapshotFrequent]?
    var lastLogged: SnapshotLogged?
    var updatedAt: Date = .distantPast
}

extension WidgetSnapshot {
    static let otherColorHex = "#8E8E93"
    static let maxSpendSegments = 6

    var isEmpty: Bool {
        rows.isEmpty && income == 0 && expense == 0
    }

    var monthName: String {
        (monthStart ?? .now).formatted(.dateTime.month(.wide))
    }

    var spendSegments: [SnapshotCategorySpend] {
        guard expense > 0 else { return [] }
        let stored = (categorySpend ?? []).filter { $0.amount > 0 }
        if stored.isEmpty {
            return [SnapshotCategorySpend(id: nil, name: "Spending", amount: expense, colorHex: Self.otherColorHex)]
        }
        return stored
    }

    mutating func resetIfMonthChanged(now: Date = .now) {
        guard let monthStart, !Calendar.current.isDate(monthStart, equalTo: now, toGranularity: .month) else { return }
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        self.monthStart = start
        monthLabel = start.formatted(.dateTime.month(.wide).year())
        income = 0
        expense = 0
        net = 0
        overLimitCount = 0
        topCategoryName = nil
        topCategoryAmount = 0
        rows = []
        categorySpend = []
        lastLogged = nil
    }

    mutating func apply(_ entry: PendingQuickLog, item: SnapshotFrequent) {
        if item.isIncome {
            income += entry.amount
            balance += entry.amount
        } else {
            expense += entry.amount
            balance -= entry.amount
            addSpend(entry.amount, item: item)
        }
        net = income - expense
        rows.insert(
            SnapshotRow(
                id: entry.id,
                title: entry.title,
                amount: entry.amount,
                isIncome: item.isIncome,
                date: entry.date,
                colorHex: item.colorHex,
                iconName: item.iconName
            ),
            at: 0
        )
        rows = Array(rows.prefix(8))
        lastLogged = SnapshotLogged(itemID: item.id, date: entry.date)
        updatedAt = entry.date
    }

    private mutating func addSpend(_ amount: Double, item: SnapshotFrequent) {
        var named = (categorySpend ?? []).filter { $0.id != nil }
        var other = (categorySpend ?? []).first { $0.id == nil }
        if let index = named.firstIndex(where: { $0.id == item.categoryID }) {
            named[index].amount += amount
        } else if named.count < Self.maxSpendSegments {
            named.append(SnapshotCategorySpend(
                id: item.categoryID,
                name: item.categoryName,
                amount: amount,
                colorHex: item.colorHex
            ))
        } else {
            other = SnapshotCategorySpend(
                id: nil,
                name: "Other",
                amount: (other?.amount ?? 0) + amount,
                colorHex: Self.otherColorHex
            )
        }
        named.sort { $0.amount > $1.amount }
        if let top = named.first {
            topCategoryName = top.name
            topCategoryAmount = top.amount
        }
        categorySpend = named + (other.map { [$0] } ?? [])
    }
}

enum WidgetStore {
    static let appGroupID = "group.com.umangsurana.idiot"
    static let snapshotKey = "widgetSnapshot"
    static let feedbackDuration: TimeInterval = 4

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return WidgetSnapshot()
        }
        snapshot.resetIfMonthChanged()
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
    }

    static func logFrequent(itemID: String) {
        var snapshot = load()
        guard let item = snapshot.frequent?.first(where: { $0.id == itemID }), item.amount > 0 else { return }
        let entry = PendingQuickLog(
            id: UUID(),
            title: item.title,
            amount: item.amount,
            categoryID: item.categoryID,
            categoryName: item.categoryName,
            type: item.type,
            date: .now
        )
        QuickLogQueue.append(entry)
        snapshot.apply(entry, item: item)
        save(snapshot)
        QuickLogQueue.notifyApp()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension Double {
    var widgetCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = abs(self).truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Color {
    init(snapshotHex hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        var value: UInt64 = 0x4F8EF7
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = .init(red: r, green: g, blue: b)
    }
}
