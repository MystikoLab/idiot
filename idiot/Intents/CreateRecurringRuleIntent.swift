import AppIntents
import Foundation
import SwiftData

nonisolated enum RecurrenceOption: String, AppEnum {
    case weekly
    case monthly
    case yearly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Frequency"
    static let caseDisplayRepresentations: [RecurrenceOption: DisplayRepresentation] = [
        .weekly: "Weekly",
        .monthly: "Monthly",
        .yearly: "Yearly",
    ]
}

struct CreateRecurringRuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Recurring Rule"
    static let description = IntentDescription("Sets up a subscription or an automatic salary that Idiot logs on schedule.")

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category")
    var category: CategoryEntity

    @Parameter(title: "Frequency", default: .monthly)
    var frequency: RecurrenceOption

    @Parameter(title: "Start Date")
    var startDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Repeat \(\.$name) for \(\.$amount) \(\.$frequency) in \(\.$category)") {
            \.$startDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = try IntentData.validatedTitle(name)
        try IntentData.validateAmount(amount)
        guard let resolved = IntentData.categories().first(where: { $0.id == category.id }) else {
            throw IntentFailure.message("That category is no longer available.")
        }

        let start = startDate ?? .now
        let recurrence = RecurrenceFrequency(rawValue: frequency.rawValue) ?? .monthly
        let rule = RecurringRule(
            title: title,
            amount: amount,
            frequency: recurrence,
            dayNumber: min(max(Calendar.current.component(.day, from: start), 1), 28),
            category: resolved,
            startDate: start
        )
        IntentData.context.insert(rule)
        RecurringEngine.materialize(context: IntentData.context)
        try IntentData.commit()

        var text = "Created \(title): \(amount.formattedCurrency) \(recurrence.label.lowercased()) in \(resolved.name)."
        if let next = RecurringEngine.nextDueDate(for: rule) {
            text += " Next on \(next.formatted(date: .abbreviated, time: .omitted))."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
