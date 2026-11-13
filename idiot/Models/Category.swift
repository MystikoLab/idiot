import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var type: CategoryType = CategoryType.expense
    var limit: Double?
    var colorHex: String = "#4F8EF7"
    var iconName: String = "tag.fill"
    var isSystem: Bool = false
    var sortOrder: Int = 0
    var budgetAlertsEnabled: Bool = true
    var syncStamp: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Transaction.category) var transactions: [Transaction]?
    @Relationship(deleteRule: .nullify, inverse: \Transaction.subCategory) var subTransactions: [Transaction]?
    @Relationship(deleteRule: .cascade, inverse: \RecurringRule.category) var recurringRules: [RecurringRule]?
    @Relationship(deleteRule: .nullify, inverse: \SavingsGoal.category) var goals: [SavingsGoal]?

    init(
        id: UUID = UUID(),
        name: String = "",
        type: CategoryType = .expense,
        limit: Double? = nil,
        colorHex: String = "#4F8EF7",
        iconName: String = "tag.fill",
        isSystem: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.limit = limit
        self.colorHex = colorHex
        self.iconName = iconName
        self.isSystem = isSystem
        self.sortOrder = sortOrder
    }
}
