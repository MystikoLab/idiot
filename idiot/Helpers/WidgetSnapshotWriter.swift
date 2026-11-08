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

struct WidgetSnapshot: Codable, Hashable {
    var monthLabel: String = ""
    var income: Double = 0
    var expense: Double = 0
    var net: Double = 0
    var balance: Double = 0
    var overLimitCount: Int = 0
    var topCategoryName: String?
    var topCategoryAmount: Double = 0
    var rows: [SnapshotRow] = []
    var updatedAt: Date = .distantPast
}

enum WidgetStore {
    static let appGroupID = "group.com.umangsurana.idiot"
    static let snapshotKey = "widgetSnapshot"
}

enum WidgetSnapshotWriter {
    static func write(context: ModelContext) {
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
            .prefix(5)
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
        var spendByCategory: [String: Double] = [:]

        for category in categories where category.type == .expense {
            let spent = txSum(monthTxs.filter { $0.category?.id == category.id }, .expense)
            if let limit = category.limit, spent > limit {
                overLimitCount += 1
            }
            if spent > 0 {
                spendByCategory[category.name] = spent
            }
        }

        if let top = spendByCategory.max(by: { $0.value < $1.value }) {
            topCategory = (top.key, top.value)
        }

        let snapshot = WidgetSnapshot(
            monthLabel: monthStart.formatted(.dateTime.month(.wide).year()),
            income: income,
            expense: expense,
            net: income - expense,
            balance: balance,
            overLimitCount: overLimitCount,
            topCategoryName: topCategory?.name,
            topCategoryAmount: topCategory?.amount ?? 0,
            rows: rows,
            updatedAt: .now
        )

        guard let defaults = UserDefaults(suiteName: WidgetStore.appGroupID) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetStore.snapshotKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func txSum(_ txs: [Transaction], _ type: CategoryType) -> Double {
        txs.filter { $0.category?.type == type }.reduce(0) { $0 + $1.amount }
    }
}
