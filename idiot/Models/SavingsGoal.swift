import Foundation
import SwiftData

@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var targetAmount: Double = 0
    var startDate: Date = Date()
    var deadline: Date?
    var iconName: String = "target"
    var colorHex: String = "#34C759"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var syncStamp: Date = Date()
    var category: Category?

    init(
        id: UUID = UUID(),
        name: String = "",
        targetAmount: Double = 0,
        startDate: Date = .now,
        deadline: Date? = nil,
        iconName: String = "target",
        colorHex: String = "#34C759",
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now,
        category: Category? = nil
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.startDate = startDate
        self.deadline = deadline
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.category = category
    }
}

extension [SavingsGoal] {
    var activeOrdered: [SavingsGoal] {
        filter { !$0.isArchived }.goalOrdered
    }

    var archivedOrdered: [SavingsGoal] {
        filter(\.isArchived).goalOrdered
    }

    private var goalOrdered: [SavingsGoal] {
        sorted { lhs, rhs in
            lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt
        }
    }
}
