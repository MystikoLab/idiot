import AppIntents
import Foundation

nonisolated struct MonthSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Month Summary"
    static let description = IntentDescription("Tells you how much you have spent, earned and kept this month. Returns the amount spent.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let transactions = IntentData.monthTransactions()
        let spent = transactions.filter { $0.category?.type == .expense }.reduce(0) { $0 + $1.amount }
        let income = transactions.filter { $0.category?.type == .income }.reduce(0) { $0 + $1.amount }
        let net = income - spent
        let month = Date.now.formatted(.dateTime.month(.wide))
        let text = "You've spent \(spent.formattedCurrency) in \(month). Income is \(income.formattedCurrency), net \(net.formattedCurrency)."
        return .result(value: spent, dialog: IntentDialog(stringLiteral: text))
    }
}
