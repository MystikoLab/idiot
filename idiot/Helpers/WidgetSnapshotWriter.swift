import Foundation
import SwiftData
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

enum WidgetStore {
    static let appGroupID = "group.com.umangsurana.idiot"
    static let snapshotKey = "widgetSnapshot"
}

enum WidgetSnapshotWriter {
    private static let maxSpendSegments = 6

    static func write(context: ModelContext) {
        NotificationManager.shared.refresh()
        QuickLogDrainer.drain(context: context)
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let transactions = try? context.fetch(descriptor) else { return }
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        let calendar = Calendar.current
        let monthStart = Date.now.startOfMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date.now.endOfMonth

        let monthTxs = transactions.filter { $0.date >= monthStart && $0.date < monthEnd }
        let income = txSum(monthTxs, .income)
        let expense = txSum(monthTxs, .expense)
        let balance = transactions
            .reduce(0) { $0 + $1.signedCashAmount } + OpeningBalance.amount

        let rows: [SnapshotRow] = monthTxs
            .prefix(8)
            .map { tx in
                SnapshotRow(
                    id: tx.id,
                    title: tx.title,
                    amount: tx.amount,
                    isIncome: tx.signedCashAmount > 0,
                    date: tx.date,
                    colorHex: tx.category?.colorHex ?? "#8E8E93",
                    iconName: tx.category?.iconName ?? "tag.fill"
                )
            }

        var overLimitCount = 0
        var topCategory: (name: String, amount: Double)?
        var categorySpend: [SnapshotCategorySpend] = []

        for category in categories where category.type == .expense {
            let spent = txSum(monthTxs.filter { $0.category?.id == category.id }, .expense)
            if let limit = category.limit, spent > limit {
                overLimitCount += 1
            }
            if spent > 0 {
                categorySpend.append(SnapshotCategorySpend(
                    id: category.id,
                    name: category.name,
                    amount: spent,
                    colorHex: category.colorHex
                ))
            }
        }

        categorySpend.sort { $0.amount > $1.amount }
        if let top = categorySpend.first {
            topCategory = (top.name, top.amount)
        }
        if categorySpend.count > maxSpendSegments {
            let rest = categorySpend[maxSpendSegments...].reduce(0) { $0 + $1.amount }
            categorySpend = Array(categorySpend.prefix(maxSpendSegments))
            categorySpend.append(SnapshotCategorySpend(id: nil, name: "Other", amount: rest, colorHex: "#8E8E93"))
        }

        guard let defaults = UserDefaults(suiteName: WidgetStore.appGroupID) else { return }

        let snapshot = WidgetSnapshot(
            monthLabel: monthStart.formatted(.dateTime.month(.wide).year()),
            monthStart: monthStart,
            income: income,
            expense: expense,
            net: income - expense,
            balance: balance,
            overLimitCount: overLimitCount,
            topCategoryName: topCategory?.name,
            topCategoryAmount: topCategory?.amount ?? 0,
            rows: rows,
            goals: goalRows(context: context),
            categorySpend: categorySpend,
            frequent: frequentRows(transactions),
            lastLogged: recentLog(in: defaults),
            updatedAt: .now
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetStore.snapshotKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func recentLog(in defaults: UserDefaults) -> SnapshotLogged? {
        guard let data = defaults.data(forKey: WidgetStore.snapshotKey),
              let logged = (try? JSONDecoder().decode(WidgetSnapshot.self, from: data))?.lastLogged,
              abs(logged.date.timeIntervalSinceNow) < 10
        else {
            return nil
        }
        return logged
    }

    private static func frequentRows(_ transactions: [Transaction]) -> [SnapshotFrequent] {
        let now = Date.now
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        let candidates = transactions.filter { tx in
            guard tx.recurringRuleID == nil, tx.amount > 0, tx.date >= cutoff, tx.date <= now else { return false }
            return tx.category?.type == .expense || tx.category?.type == .income
        }
        return TransactionMatcher.titleGroups(candidates)
            .filter { $0.count >= 2 }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.latest.date > rhs.latest.date
            }
            .prefix(4)
            .compactMap { group in
                guard let category = group.latest.category else { return nil }
                return SnapshotFrequent(
                    id: group.id,
                    title: group.latest.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: group.latest.amount,
                    categoryID: category.id,
                    categoryName: category.name,
                    colorHex: category.colorHex,
                    iconName: category.iconName,
                    type: category.type.rawValue
                )
            }
    }

    private static func goalRows(context: ModelContext) -> [SnapshotGoal] {
        let goals = (try? context.fetch(FetchDescriptor<SavingsGoal>())) ?? []
        return goals.activeOrdered.prefix(5).map { goal in
            let progress = GoalEngine.progress(for: goal)
            return SnapshotGoal(
                id: progress.id,
                name: progress.name,
                saved: progress.saved,
                target: progress.target,
                status: progress.status.rawValue,
                deadline: progress.deadline,
                colorHex: progress.colorHex,
                iconName: progress.iconName
            )
        }
    }

    private static func txSum(_ txs: [Transaction], _ type: CategoryType) -> Double {
        txs.filter { $0.category?.type == type }.reduce(0) { $0 + $1.amount }
    }
}
