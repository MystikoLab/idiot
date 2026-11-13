import AppIntents

nonisolated struct IdiotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Log spending in \(.applicationName)",
            ],
            shortTitle: "Log Expense",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: LogIncomeIntent(),
            phrases: [
                "Log income in \(.applicationName)",
                "Add income to \(.applicationName)",
            ],
            shortTitle: "Log Income",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: MonthSummaryIntent(),
            phrases: [
                "How much have I spent this month in \(.applicationName)",
                "\(.applicationName) month summary",
                "What did I spend this month in \(.applicationName)",
            ],
            shortTitle: "Month Summary",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: OpenAddFormIntent(),
            phrases: [
                "Add a transaction in \(.applicationName)",
                "New transaction in \(.applicationName)",
            ],
            shortTitle: "Add Transaction",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: CreateRecurringRuleIntent(),
            phrases: [
                "New subscription in \(.applicationName)",
                "Create a recurring rule in \(.applicationName)",
            ],
            shortTitle: "New Recurring Rule",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
