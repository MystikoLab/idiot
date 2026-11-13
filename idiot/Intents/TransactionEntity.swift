import AppIntents
import Foundation
import SwiftData

nonisolated struct TransactionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction"
    static let defaultQuery = TransactionEntityQuery()

    let id: UUID
    let title: String
    let amountText: String
    let dateText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(amountText) · \(dateText)")
    }
}

extension TransactionEntity {
    @MainActor
    init(_ transaction: Transaction) {
        let sign = transaction.signedCashAmount > 0 ? "+" : "−"
        self.init(
            id: transaction.id,
            title: transaction.title.isEmpty ? "Untitled" : transaction.title,
            amountText: sign + transaction.amount.formattedCurrency,
            dateText: transaction.date.formatted(date: .abbreviated, time: .omitted)
        )
    }
}

nonisolated struct TransactionEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TransactionEntity] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { identifiers.contains($0.id) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try IntentData.context.fetch(descriptor).map(TransactionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TransactionEntity] {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.title.localizedStandardContains(string) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return try IntentData.context.fetch(descriptor).map(TransactionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TransactionEntity] {
        IntentData.monthTransactions().prefix(15).map(TransactionEntity.init)
    }
}
