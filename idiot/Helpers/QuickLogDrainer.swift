import Foundation
import SwiftData

enum QuickLogDrainer {
    private static var isObserving = false

    @discardableResult
    static func drain(context: ModelContext) -> Bool {
        let pending = QuickLogQueue.load()
        guard !pending.isEmpty,
              let categories = try? context.fetch(FetchDescriptor<Category>()),
              !categories.isEmpty
        else {
            return false
        }

        let ids = pending.map(\.id)
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { ids.contains($0.id) })
        guard let existing = try? context.fetch(descriptor) else { return false }

        var known = Set(existing.map(\.id))
        var inserted = false
        for entry in pending where !known.contains(entry.id) {
            known.insert(entry.id)
            guard entry.amount > 0, let category = category(for: entry, in: categories) else { continue }
            context.insert(Transaction(
                id: entry.id,
                title: entry.title,
                amount: entry.amount,
                date: entry.date,
                category: category
            ))
            inserted = true
        }

        if inserted {
            do {
                try context.save()
            } catch {
                context.rollback()
                return false
            }
        }
        QuickLogQueue.remove(ids: Set(ids))
        return inserted
    }

    static func drainAndRefresh() {
        guard !QuickLogQueue.load().isEmpty else { return }
        WidgetSnapshotWriter.write(context: AppModelContainer.shared.mainContext)
    }

    static func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    QuickLogDrainer.drainAndRefresh()
                }
            },
            QuickLogQueue.changeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static func category(for entry: PendingQuickLog, in categories: [Category]) -> Category? {
        if let match = categories.first(where: { $0.id == entry.categoryID }) {
            return match
        }
        return categories.first {
            $0.type.rawValue == entry.type && $0.name.caseInsensitiveCompare(entry.categoryName) == .orderedSame
        }
    }
}
