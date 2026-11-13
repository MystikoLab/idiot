import Foundation
import Observation
import SwiftData
import UserNotifications
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

enum NotificationSettings {
    static let budgetAlertsKey = "notifyBudgetAlerts"
    static let recurringRemindersKey = "notifyRecurringReminders"
    static let warningThresholdKey = "budgetWarningThreshold"
    static let reminderMinutesKey = "recurringReminderMinutes"
    static let budgetRecordKey = "budgetAlertRecord"
    static let scheduledReminderIDsKey = "recurringReminderIDs"

    static let defaultWarningThreshold = 80
    static let warningThresholdRange = 50 ... 95
    static let defaultReminderMinutes = 9 * 60

    static var budgetAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: budgetAlertsKey)
    }

    static var recurringRemindersEnabled: Bool {
        UserDefaults.standard.bool(forKey: recurringRemindersKey)
    }

    static var warningThreshold: Int {
        let stored = UserDefaults.standard.object(forKey: warningThresholdKey) as? Int ?? defaultWarningThreshold
        return min(max(stored, warningThresholdRange.lowerBound), warningThresholdRange.upperBound)
    }

    static var reminderMinutes: Int {
        let stored = UserDefaults.standard.object(forKey: reminderMinutesKey) as? Int ?? defaultReminderMinutes
        return min(max(stored, 0), 24 * 60 - 1)
    }
}

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    enum BudgetAlertKind: String {
        case warning
        case over
    }

    struct BudgetStatus {
        let categoryID: UUID
        let name: String
        let limit: Double
        let spent: Double
        let alertsEnabled: Bool
    }

    struct BudgetAlert {
        let status: BudgetStatus
        let kind: BudgetAlertKind
    }

    struct BudgetDecision {
        var alerts: [BudgetAlert] = []
        var marks: Set<String> = []
    }

    struct RecurringReminder {
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
    }

    static let recurringIdentifierPrefix = "recurring-"
    static let budgetIdentifierPrefix = "budget-"
    static let reminderHorizonDays = 60
    static let maxReminders = 40

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var silenceNextBudgetPass = false

    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        center.delegate = self

        #if os(macOS)
            let activeName = NSApplication.didBecomeActiveNotification
        #else
            let activeName = UIApplication.didBecomeActiveNotification
        #endif

        Task {
            for await _ in NotificationCenter.default.notifications(named: activeName) {
                await refreshAuthorization()
                refresh()
            }
        }

        Task {
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                refresh()
            }
        }

        Task {
            await refreshAuthorization()
            refresh()
        }
    }

    // MARK: Authorization

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let granted = await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    static var systemSettingsURL: URL? {
        #if os(macOS)
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #else
            URL(string: UIApplication.openNotificationSettingsURLString)
        #endif
    }

    // MARK: Refresh

    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            evaluateBudgets()
            scheduleRecurringReminders()
        }
    }

    func budgetSettingsChanged() {
        silenceNextBudgetPass = true
        if !NotificationSettings.budgetAlertsEnabled {
            removeBudgetNotifications()
        }
        refresh()
    }

    func recurringSettingsChanged() {
        refresh()
    }

    // MARK: Budget alerts

    private func evaluateBudgets() {
        let silent = silenceNextBudgetPass
        silenceNextBudgetPass = false
        guard NotificationSettings.budgetAlertsEnabled, let context = container?.mainContext else { return }

        let now = Date.now
        let monthKey = Self.monthKey(for: now)
        let statuses = Self.budgetStatuses(context: context, now: now)
        let stored = UserDefaults.standard.stringArray(forKey: NotificationSettings.budgetRecordKey) ?? []
        let seen = Set(stored.filter { $0.hasPrefix(monthKey + "|") })

        let decision = Self.budgetDecision(
            statuses: statuses,
            warningThreshold: Double(NotificationSettings.warningThreshold) / 100,
            seen: seen,
            monthKey: monthKey
        )

        let updated = seen.union(decision.marks)
        if updated != Set(stored) {
            UserDefaults.standard.set(updated.sorted(), forKey: NotificationSettings.budgetRecordKey)
        }

        guard !silent, !isDenied else { return }
        let daysLeft = Self.daysLeftInMonth(from: now)
        for alert in decision.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.kind == .over ? "Budget reached" : "Budget warning"
            content.body = Self.budgetBody(for: alert, daysLeft: daysLeft)
            content.sound = .default
            let identifier = "\(Self.budgetIdentifierPrefix)\(Self.recordKey(monthKey: monthKey, categoryID: alert.status.categoryID, kind: alert.kind))"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    private func removeBudgetNotifications() {
        let stored = UserDefaults.standard.stringArray(forKey: NotificationSettings.budgetRecordKey) ?? []
        let identifiers = stored.map { Self.budgetIdentifierPrefix + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func budgetStatuses(context: ModelContext, now: Date) -> [BudgetStatus] {
        let monthStart = now.startOfMonth
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? now.endOfMonth
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.date >= monthStart && tx.date < monthEnd
            }
        )
        guard let transactions = try? context.fetch(descriptor) else { return [] }
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        var spentByCategory: [UUID: Double] = [:]
        for transaction in transactions {
            guard let category = transaction.category, category.type == .expense else { continue }
            spentByCategory[category.id, default: 0] += transaction.amount
        }

        return categories.compactMap { category in
            guard category.type == .expense, let limit = category.limit, limit > 0 else { return nil }
            return BudgetStatus(
                categoryID: category.id,
                name: category.name,
                limit: limit,
                spent: spentByCategory[category.id] ?? 0,
                alertsEnabled: category.budgetAlertsEnabled
            )
        }
    }

    static func budgetDecision(statuses: [BudgetStatus], warningThreshold: Double, seen: Set<String>, monthKey: String) -> BudgetDecision {
        var decision = BudgetDecision()
        for status in statuses where status.limit > 0 {
            let ratio = status.spent / status.limit
            let warningKey = recordKey(monthKey: monthKey, categoryID: status.categoryID, kind: .warning)
            let overKey = recordKey(monthKey: monthKey, categoryID: status.categoryID, kind: .over)

            if ratio >= 1 {
                if !seen.contains(overKey), status.alertsEnabled {
                    decision.alerts.append(BudgetAlert(status: status, kind: .over))
                }
                decision.marks.insert(overKey)
                decision.marks.insert(warningKey)
            } else if ratio >= warningThreshold {
                if !seen.contains(warningKey), status.alertsEnabled {
                    decision.alerts.append(BudgetAlert(status: status, kind: .warning))
                }
                decision.marks.insert(warningKey)
            }
        }
        return decision
    }

    static func budgetBody(for alert: BudgetAlert, daysLeft: Int) -> String {
        let status = alert.status
        let limitText = status.limit.formattedCurrency
        switch alert.kind {
        case .warning:
            let percent = Int((status.spent / status.limit * 100).rounded(.down))
            let left = max(status.limit - status.spent, 0).formattedCurrency
            return "\(status.name) is at \(percent)% of its \(limitText) budget — \(left) left for \(daysLeft) day\(daysLeft == 1 ? "" : "s")."
        case .over:
            let excess = status.spent - status.limit
            if excess < 0.005 {
                return "\(status.name) has reached its \(limitText) budget."
            }
            return "\(status.name) is over its \(limitText) budget by \(excess.formattedCurrency)."
        }
    }

    static func recordKey(monthKey: String, categoryID: UUID, kind: BudgetAlertKind) -> String {
        "\(monthKey)|\(categoryID.uuidString)|\(kind.rawValue)"
    }

    static func monthKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func daysLeftInMonth(from date: Date) -> Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 1 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: interval.end).day ?? 1
        return max(days, 1)
    }

    // MARK: Recurring reminders

    private func scheduleRecurringReminders() {
        let defaults = UserDefaults.standard
        let previous = defaults.stringArray(forKey: NotificationSettings.scheduledReminderIDsKey) ?? []
        if !previous.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: previous)
        }

        guard NotificationSettings.recurringRemindersEnabled, !isDenied, let context = container?.mainContext else {
            if !previous.isEmpty {
                defaults.removeObject(forKey: NotificationSettings.scheduledReminderIDsKey)
            }
            return
        }

        let now = Date.now
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let horizon = Calendar.current.date(byAdding: .day, value: Self.reminderHorizonDays, to: now) ?? now
        let occurrences = AnalyticsEngine.upcomingOccurrences(rules: rules, until: horizon, after: now)
        let reminders = Self.recurringReminders(
            occurrences: occurrences,
            reminderMinutes: NotificationSettings.reminderMinutes,
            now: now
        )

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }

        defaults.set(reminders.map(\.identifier), forKey: NotificationSettings.scheduledReminderIDsKey)
    }

    static func recurringReminders(occurrences: [AnalyticsEngine.UpcomingOccurrence], reminderMinutes: Int, now: Date) -> [RecurringReminder] {
        let calendar = Calendar.current
        let reminders: [RecurringReminder] = occurrences.compactMap { occurrence in
            let dueDay = calendar.startOfDay(for: occurrence.date)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDay),
                  let fireDate = calendar.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: dayBefore),
                  fireDate > now
            else { return nil }

            let isIncome = occurrence.amount > 0
            let amountText = abs(occurrence.amount).formattedCurrency
            return RecurringReminder(
                identifier: recurringIdentifierPrefix + occurrence.id,
                title: isIncome ? "Income tomorrow" : "Payment due tomorrow",
                body: "\(occurrence.title) — \(amountText) \(isIncome ? "arrives" : "is due") tomorrow",
                fireDate: fireDate
            )
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(maxReminders))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
