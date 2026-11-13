# Phase 22 — App Intents, spending widgets, Quick Log

Shortcuts/Siri actions that work without opening the app, widgets rebuilt around a segmented monthly spending bar, a one-tap Quick Log widget and a Control Center button.

## Implementation guide

- **Shared container** (`Helpers/AppModelContainer.swift`): `AppModelContainer.shared` is the only `ModelContainer(` in the project. `idiotApp` uses it and intents reach it through `IntentData.context` (`mainContext`). App intents run in the app process (the system launches it in the background), so nothing opens the store from another process.
- **Intents** (`idiot/Intents/`):
  - `LogExpenseIntent` / `LogIncomeIntent`: amount, title, optional category (options limited by `ExpenseCategoryOptions` / `IncomeCategoryOptions`), optional date. With no category, `AutoCategorizer.History` picks the most-used category for the normalized title; with no history the intent asks via `requestDisambiguation`. Shared logic is `TransactionLogger.log`.
  - `MonthSummaryIntent`: dialog with spent, income and net for the current month; the returned value is the spent amount (`Double`).
  - `OpenAddFormIntent` (`openAppWhenRun`): sets a time-stamped flag in app-group defaults and posts `AddFormRequest.notification`; `ContentView` consumes it on appear, on the notification and on becoming active, and shows the same sheet as `idiot://add`. This file is compiled into both targets.
  - `CreateRecurringRuleIntent`: name, amount, category (any type), frequency (`RecurrenceOption` `AppEnum` mapped to `RecurrenceFrequency`), start date. Inserts the rule like `RecurringFormView` and runs `RecurringEngine.materialize`. Day of month is taken from the start date (capped at 28).
  - `EditTransactionIntent`: `TransactionEntity` (`Transaction.id`, `EntityStringQuery` over titles, suggestions = latest 15 of the current month) plus optional new title, amount, category, date. Everything is validated before anything is changed. Refuses when `IntentData.isLocked` (the `lockPastMonths` setting and `Date.isInPastMonth`) is true for the transaction or for the new date.
  - `CategoryEntity` + `CategoryEntityQuery`; `IdiotShortcuts` (`AppShortcutsProvider`) exposes Log Expense, Log Income, Month Summary, Add Transaction and New Recurring Rule.
  - Every write goes through `IntentData.commit()`: save (rollback on failure), then `WidgetSnapshotWriter.write`, which also refreshes notifications and reloads widget timelines.
  - With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, entities, queries and parameterless intents are `nonisolated` with `@MainActor` methods. Intents that use `@Parameter` are left unannotated because `nonisolated` on the type warns about the wrapped properties.
- **Snapshot** (`WidgetSnapshot`, duplicated in `Helpers/WidgetSnapshotWriter.swift` and `IdiotWidgets/WidgetSnapshot.swift`), all new fields optional:
  - `monthStart`: the widget clears the month figures itself when the month has rolled over, and timelines refresh at the start of the next month.
  - `categorySpend`: this month's expense per primary category, descending, top 6 plus an "Other" bucket (`id == nil`).
  - `frequent`: up to 4 `SnapshotFrequent` from `TransactionMatcher.titleGroups` over the last 6 months of non-recurring income and expense transactions, at least 2 uses, most used first; amount and category come from the latest one.
  - `lastLogged`: set by the widget for the tap feedback; the writer carries it over for 10 seconds.
  - `rows` now holds 8 transactions.
- **Widgets** (`IdiotWidgets/Widgets.swift`): all use `containerBackground(.background, for: .widget)`, system content margins, top-leading layouts, `privacySensitive` amounts with `minimumScaleFactor`, and `widgetAccentable` marks. Kind strings are unchanged.
  - `SpendingBar`: always full width = total spent; one `UnevenRoundedRectangle` per category with 2 pt gaps, fully rounded outer ends and a minimum width (`SpendingBar.widths`). Outside full-colour rendering the segments step down in opacity so they stay distinguishable. Empty state is a neutral capsule.
  - `AnalyticsWidget` ("Monthly Spending"): small = total, bar, 2 legend entries, whole widget opens the add form; medium = total, bar, 4 legend entries in two columns, `+` link; large = bar, full legend with percentages, income/net and over-budget count or top category.
  - `TransactionWidget`: spent total, income, slim bar, recent rows (`ViewThatFits` picks how many).
  - `NewTransactionWidget`, `SavingsGoalsWidget`: visual clean-up only.
- **Quick Log** (`IdiotWidgets/QuickLogWidget.swift`, kind `QuickLogWidget`, small = 2 buttons, medium = 4 buttons and a `+` link):
  - `QuickLogIntent` exists only in the widget target, so it runs in the extension and never touches SwiftData. `WidgetStore.logFrequent` appends a `PendingQuickLog` to `QuickLogQueue` (app-group defaults, `Helpers/QuickLogQueue.swift`, compiled into both targets), applies it to the stored snapshot (`WidgetSnapshot.apply`: totals, category spend, recent rows, `lastLogged`), posts a Darwin notification and reloads timelines.
  - `QuickLogDrainer.drain` (app) turns the queue into `Transaction`s whose `id` is the pending entry id, skipping ids that already exist. A missing category falls back to one with the same name and type, otherwise the entry is dropped. It runs at launch, at the start of every `WidgetSnapshotWriter.write`, when the app becomes active, and half a second after the Darwin notification when the app is already running.
  - Feedback: for 4 seconds the tapped button shows a checkmark and "Logged" (a second timeline entry ends it).
- **Control Center** (iOS 18+): `LogTransactionControl` is a `ControlWidgetButton` running `OpenAddFormIntent`.
- **Project file**: the widget target lists its sources explicitly. Added `QuickLogWidget.swift`, plus references to `idiot/Helpers/QuickLogQueue.swift` and `idiot/Intents/OpenAddFormIntent.swift` so they compile in both targets.
- No schema change and nothing to deploy in CloudKit.
