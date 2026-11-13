import AppIntents
import Foundation
import SwiftData

enum TransactionLogger {
    static func log(
        title: String,
        amount: Double,
        date: Date?,
        type: CategoryType,
        provided: CategoryEntity?,
        ask: ([CategoryEntity], String) async throws -> CategoryEntity
    ) async throws -> IntentDialog {
        let cleanTitle = try IntentData.validatedTitle(title)
        try IntentData.validateAmount(amount)

        let options = IntentData.categories(type)
        guard !options.isEmpty else {
            throw IntentFailure.message("Add \(type == .income ? "an income" : "an expense") category in Idiot first.")
        }

        var category = provided.flatMap { entity in options.first { $0.id == entity.id } }
        if category == nil, provided == nil {
            let history = try AutoCategorizer.History(IntentData.context.fetch(FetchDescriptor<Transaction>()))
            category = history.category(for: cleanTitle, among: options)
        }
        if category == nil {
            let picked = try await ask(options.map(CategoryEntity.init), cleanTitle)
            category = options.first { $0.id == picked.id }
        }
        guard let category else {
            throw IntentFailure.message("That category is no longer available.")
        }

        IntentData.context.insert(Transaction(
            title: cleanTitle,
            amount: amount,
            date: date ?? .now,
            category: category
        ))
        try IntentData.commit()

        let verb = type == .income ? "Added" : "Logged"
        return IntentDialog(stringLiteral: "\(verb) \(amount.formattedCurrency) for \(cleanTitle) in \(category.name).")
    }
}

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense"
    static let description = IntentDescription("Adds an expense without opening Idiot. Leave the category empty to reuse the one you normally pick for that title.")

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Category", optionsProvider: ExpenseCategoryOptions())
    var category: CategoryEntity?

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) spent on \(\.$title)") {
            \.$category
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await TransactionLogger.log(
            title: title,
            amount: amount,
            date: date,
            type: .expense,
            provided: category
        ) { options, name in
            try await $category.requestDisambiguation(among: options, dialog: "Which category is \(name) in?")
        }
        return .result(dialog: dialog)
    }
}

struct LogIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Income"
    static let description = IntentDescription("Adds income without opening Idiot. Leave the category empty to reuse the one you normally pick for that title.")

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Category", optionsProvider: IncomeCategoryOptions())
    var category: CategoryEntity?

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) received from \(\.$title)") {
            \.$category
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await TransactionLogger.log(
            title: title,
            amount: amount,
            date: date,
            type: .income,
            provided: category
        ) { options, name in
            try await $category.requestDisambiguation(among: options, dialog: "Which category is \(name) in?")
        }
        return .result(dialog: dialog)
    }
}
