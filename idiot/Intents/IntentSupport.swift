import AppIntents
import Foundation
import SwiftData

nonisolated enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case message(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .message(text):
            "\(text)"
        }
    }
}

enum IntentData {
    static var context: ModelContext {
        AppModelContainer.shared.mainContext
    }

    static func categories(_ type: CategoryType? = nil) -> [Category] {
        let all = (try? context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard let type else { return all }
        return all.filter { $0.type == type }
    }

    static func transaction(id: UUID) -> Transaction? {
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func monthTransactions(for date: Date = .now) -> [Transaction] {
        let start = date.startOfMonth
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? date.endOfMonth
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntentFailure.message("The title can't be empty.")
        }
        return trimmed
    }

    static func validateAmount(_ amount: Double) throws {
        guard amount.isFinite, amount > 0 else {
            throw IntentFailure.message("The amount must be greater than 0.")
        }
    }

    static func isLocked(_ date: Date) -> Bool {
        let lockPastMonths = UserDefaults.standard.object(forKey: "lockPastMonths") as? Bool ?? true
        return lockPastMonths && date.isInPastMonth
    }

    static func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw IntentFailure.message("Could not save: \(error.localizedDescription)")
        }
        WidgetSnapshotWriter.write(context: context)
    }
}
