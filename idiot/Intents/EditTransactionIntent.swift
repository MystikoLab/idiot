import AppIntents
import Foundation
import SwiftData

struct EditTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Edit Transaction"
    static let description = IntentDescription("Changes the title, amount, category or date of a transaction. Only the values you fill in are changed.")

    @Parameter(title: "Transaction")
    var transaction: TransactionEntity

    @Parameter(title: "New Title")
    var newTitle: String?

    @Parameter(title: "New Amount")
    var newAmount: Double?

    @Parameter(title: "New Category")
    var newCategory: CategoryEntity?

    @Parameter(title: "New Date")
    var newDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Edit \(\.$transaction)") {
            \.$newTitle
            \.$newAmount
            \.$newCategory
            \.$newDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = IntentData.transaction(id: transaction.id) else {
            throw IntentFailure.message("That transaction no longer exists.")
        }
        guard !IntentData.isLocked(target.date) else {
            throw IntentFailure.message("\(transaction.title) is in a past month, and past months are locked from editing.")
        }
        if let newDate, IntentData.isLocked(newDate) {
            throw IntentFailure.message("That date is in a past month, and past months are locked from editing.")
        }

        let cleanTitle = try newTitle.map(IntentData.validatedTitle)
        if let newAmount {
            try IntentData.validateAmount(newAmount)
        }
        var resolvedCategory: Category?
        if let newCategory {
            resolvedCategory = IntentData.categories().first { $0.id == newCategory.id }
            guard resolvedCategory != nil else {
                throw IntentFailure.message("That category is no longer available.")
            }
        }

        var changes: [String] = []
        if let cleanTitle {
            target.title = cleanTitle
            changes.append("title \(cleanTitle)")
        }
        if let newAmount {
            target.amount = newAmount
            changes.append("amount \(newAmount.formattedCurrency)")
        }
        if let resolvedCategory {
            target.category = resolvedCategory
            if target.subCategory?.id == resolvedCategory.id {
                target.subCategory = nil
            }
            if resolvedCategory.type != .investment {
                target.isInvestmentReturn = false
            }
            changes.append("category \(resolvedCategory.name)")
        }
        if let newDate {
            target.date = newDate
            changes.append("date \(newDate.formatted(date: .abbreviated, time: .omitted))")
        }

        guard !changes.isEmpty else {
            throw IntentFailure.message("Nothing to change. Fill in at least one new value.")
        }
        try IntentData.commit()
        return .result(dialog: IntentDialog(stringLiteral: "Updated \(transaction.title): \(changes.joined(separator: ", "))."))
    }
}
