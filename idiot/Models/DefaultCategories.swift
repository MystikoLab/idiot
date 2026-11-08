import Foundation
import SwiftData

enum DefaultCategories {
    private static let didSeedKey = "didSeedCategories"
    private static let didAddInvestmentsKey = "didAddInvestmentTypeCategory"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else {
            return
        }

        let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard count == 0 else {
            UserDefaults.standard.set(true, forKey: didSeedKey)
            return
        }

        seed(context: context)
        UserDefaults.standard.set(true, forKey: didSeedKey)
    }

    static func seed(context: ModelContext) {
        let categories = [
            Category(name: "Business", type: .expense, colorHex: "#4F8EF7", iconName: "briefcase.fill", isSystem: true, sortOrder: 1),
            Category(name: "Utilities", type: .expense, colorHex: "#FF9500", iconName: "bolt.fill", isSystem: true, sortOrder: 2),
            Category(name: "Food", type: .expense, colorHex: "#FF3B30", iconName: "fork.knife", isSystem: true, sortOrder: 3),
            Category(name: "Groceries", type: .expense, colorHex: "#34C759", iconName: "basket.fill", isSystem: true, sortOrder: 4),
            Category(name: "Transport", type: .expense, colorHex: "#FFCC00", iconName: "car.fill", isSystem: true, sortOrder: 5),
            Category(name: "Technology", type: .expense, colorHex: "#AF52DE", iconName: "desktopcomputer", isSystem: true, sortOrder: 6),
            Category(name: "Personal", type: .expense, colorHex: "#FF2D55", iconName: "person.fill", isSystem: true, sortOrder: 7),
            Category(name: "Salary", type: .income, colorHex: "#34C759", iconName: "dollarsign.circle.fill", isSystem: true, sortOrder: 1),
            Category(name: "Side Hustle", type: .income, colorHex: "#5AC8FA", iconName: "bag.fill", isSystem: true, sortOrder: 2),
            investmentsCategory(sortOrder: 1),
        ]

        categories.forEach(context.insert)

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to seed default categories: \(error.localizedDescription)")
        }
    }

    static func addMissingDefaults(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didAddInvestmentsKey) else {
            return
        }

        guard let categories = try? context.fetch(FetchDescriptor<Category>()) else { return }

        let existing = categories.first {
            $0.name.compare("Investments", options: .caseInsensitive) == .orderedSame
        }
        if let existing {
            if existing.isSystem, existing.type == .expense {
                existing.type = .investment
                existing.colorHex = "#FFB300"
                existing.limit = nil
                existing.sortOrder = 1
            }
        } else if !categories.contains(where: { $0.type == .investment }) {
            context.insert(investmentsCategory(sortOrder: 1))
        }
        try? context.save()

        UserDefaults.standard.set(true, forKey: didAddInvestmentsKey)
    }

    private static func investmentsCategory(sortOrder: Int) -> Category {
        Category(name: "Investments", type: .investment, colorHex: "#FFB300", iconName: "chart.line.uptrend.xyaxis", isSystem: true, sortOrder: sortOrder)
    }

    static func reconcileDuplicates(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        guard let categories = try? context.fetch(descriptor) else { return }

        var seen: [String: Category] = [:]
        var duplicates: [(duplicate: Category, survivor: Category)] = []

        for category in categories where category.isSystem {
            let key = "\(category.type.rawValue)|\(category.name)"
            if let existing = seen[key] {
                let existingCount = existing.transactions?.count ?? 0
                let newCount = category.transactions?.count ?? 0
                if newCount > existingCount {
                    duplicates.append((existing, category))
                    seen[key] = category
                } else {
                    duplicates.append((category, existing))
                }
            } else {
                seen[key] = category
            }
        }

        guard !duplicates.isEmpty else { return }

        for (duplicate, survivor) in duplicates {
            for transaction in duplicate.transactions ?? [] {
                transaction.category = survivor
            }
            context.delete(duplicate)
        }

        try? context.save()
    }
}
