# AGENTS.md — Finance Tracker macOS + iOS App

## Project Overview

A macOS + iOS SwiftUI finance tracking app with SwiftData persistence. The app tracks both income and expense transactions across customizable categories, visualizes spending with Swift Charts (weekly income/expense/investment line chart (expense axis left, income axis right, investments on an unlabeled scale) + multi-month trend line charts + a full Analytics suite), enforces category budgets, supports recurring transaction rules, iCloud sync, widgets (monthly spending bar, recent transactions, savings goals, one-tap Quick Log, a Control Center button on iOS 18+), App Intents for Shortcuts and Siri, and locks past-month data from editing.

**Stack**: SwiftUI + SwiftData + Swift Charts + CloudKit  
**Target**: macOS 14+ / iOS 17+  
**Tooling**: SwiftFormat (`make format`), Xcode 26.5

## Architecture

### Directory Structure
```
idiot/
├── Models/
│   ├── Transaction.swift
│   ├── Category.swift
│   ├── CategoryType.swift
│   ├── RecurringRule.swift
│   ├── Attachment.swift (receipt image / PDF attached to a transaction)
│   ├── RecurrenceFrequency.swift
│   ├── SavingsGoal.swift
│   └── DefaultCategories.swift
├── ViewModels/
│   ├── CloudSyncMonitor.swift
│   └── MCPServerController.swift (macOS)
├── Views/
│   ├── TransactionListView.swift
│   ├── TransactionRowView.swift
│   ├── TransactionFormView.swift
│   ├── TransactionSuggestionList.swift (frequent-transaction suggestions under the title field)
│   ├── ReceiptsSection.swift (form section: receipt thumbnails, add menu, OCR suggestion chips, iOS document scanner)
│   ├── SimilarTransactionsView.swift (sheet: all transactions with the same normalized title)
│   ├── CSVImportView.swift (review/edit rows before importing)
│   ├── CSVExportView.swift (date range + category filters)
│   ├── MCPSettingsSection.swift (macOS)
│   ├── MenuBarView.swift (macOS menu bar extra)
│   ├── HelpView.swift (help & savings guide, opened from header ? button or Settings)
│   ├── RecurringListView.swift
│   ├── RecurringFormView.swift
│   ├── SettingsView.swift
│   ├── SavingsGoalListView.swift + SavingsGoalFormView.swift (Settings > Savings Goals)
│   ├── GoalsStripView.swift (main screen goals strip) + GoalStatusBadge.swift
│   ├── GoalsSection.swift + GoalCardView.swift (Analytics Goals tab)
│   ├── RecategorizeView.swift (review sheet for "Re-categorize this month…")
│   ├── CategoryEditView.swift
│   ├── MonthlyHeaderView.swift
│   ├── WeeklyChartView.swift
│   ├── SummaryBarView.swift
│   ├── TrendChartView.swift
│   └── AnalyticsView.swift (+ HeatmapSection, BalanceChartSection,
│        InsightsSection, ForecastSection, PeriodComparisonSection,
│        RecurringSplitSection, SpendPatternsSection, RepeatSpendingSection,
│        InvestmentsSection)
├── Helpers/
│   ├── DateExtensions.swift
│   ├── ColorExtensions.swift
│   ├── NumberFormatterExtensions.swift
│   ├── AnalyticsGranularity.swift
│   ├── AnalyticsEngine.swift
│   ├── RecurringEngine.swift
│   ├── GoalEngine.swift (savings goal progress math)
│   ├── TransactionMatcher.swift (title normalization, suggestions, similar transactions)
│   ├── CategoryMatchMode.swift (main / sub / either category matching for filters)
│   ├── AutoCategorizer.swift (Apple Intelligence availability, category history lookup, on-device model call)
│   ├── AttachmentProcessor.swift (image downscale / JPEG, receipt import sources, Quick Look temp files)
│   ├── ReceiptScanner.swift (Vision OCR: amount, merchant, date)
│   ├── WidgetSnapshotWriter.swift
│   ├── AppModelContainer.swift (the single shared ModelContainer)
│   ├── QuickLogQueue.swift (pending widget logs, also compiled into the widget target)
│   ├── QuickLogDrainer.swift
│   ├── NotificationManager.swift (local notifications: budget alerts, recurring reminders)
│   ├── MCPTools.swift (macOS)
│   ├── MCPProtocol.swift (macOS)
│   ├── MCPHTTPServer.swift (macOS)
│   ├── CSVImporter.swift
│   └── CSVExporter.swift
├── Intents/
│   ├── IntentSupport.swift, CategoryEntity.swift, TransactionEntity.swift
│   ├── LogTransactionIntents.swift, MonthSummaryIntent.swift, EditTransactionIntent.swift
│   ├── CreateRecurringRuleIntent.swift, IdiotShortcuts.swift
│   └── OpenAddFormIntent.swift (also compiled into the widget target)
├── Resources/
│   └── (Assets, etc.)
├── idiotApp.swift
└── ContentView.swift
```

`IdiotWidgets/` (widget extension, sources listed explicitly in the project file): `IdiotWidgets.swift` (bundle), `WidgetSnapshot.swift` (snapshot model + app-group store), `Widgets.swift` (Recent Transactions, Monthly Spending, New Transaction, Savings Goals, shared `SpendingBar`), `QuickLogWidget.swift` (Quick Log widget + intent, Control Center button).

### Data Models (SwiftData)

**`Category`** — `@Model`
- `id: UUID` (unique)
- `name: String`
- `type: CategoryType` (enum: `.income` / `.expense` / `.investment`)
- `limit: Double?` (monthly spending cap for expense categories; nil = no limit)
- `colorHex: String` (hex color for chart segments and badges)
- `iconName: String` (SF Symbol name)
- `isSystem: Bool` (true for default categories; system categories can be renamed, recolored via a custom ColorPicker, and deleted — they are not re-seeded after deletion)
- `sortOrder: Int`
- `budgetAlertsEnabled: Bool` (default true; per-category mute for budget alert notifications)
- `subTransactions: [Transaction]?` (inverse of `Transaction.subCategory`, delete rule nullify)

**`Transaction`** — `@Model`
- `id: UUID`
- `title: String`
- `desc: String?`
- `amount: Double`
- `date: Date`
- `category: Category` (relationship; the main category — owns the amount for budgets, charts, totals and analytics)
- `subCategory: Category?` (optional second label only; never splits the amount; filters choose main / sub / either via `CategoryMatchMode`)
- `createdAt: Date`
- `isInvestmentReturn: Bool` (investment categories only: `false` = contribution, `true` = return such as a sale or dividend)
- `attachments: [Attachment]?` (receipts; cascade delete; use `hasAttachments` in lists so `data` is never loaded)

**`Attachment`** — `@Model`
- `id: UUID`
- `filename: String`
- `contentType: String` (UTType identifier; images are stored as downscaled JPEG, PDFs untouched)
- `data: Data?` (`@Attribute(.externalStorage)`)
- `createdAt: Date`
- `transaction: Transaction?`

**`SavingsGoal`** — `@Model`
- `id: UUID`, `name: String`, `targetAmount: Double`
- `startDate: Date`, `deadline: Date?`
- `iconName: String`, `colorHex: String`, `sortOrder: Int`, `isArchived: Bool`, `createdAt: Date`
- `category: Category?` (inverse `Category.goals`, nullified when the category is deleted)
- Progress = money logged in the linked category from `startDate` onward (investment: contributions − returns; income/expense: sum of amounts), computed by `GoalEngine`.

### CategoryType Enum
```swift
enum CategoryType: String, Codable, CaseIterable {
    case income
    case expense
    case investment
}
```

Investment categories act as holdings that group contributions and returns. Net invested = contributions − returns (`[Transaction].netInvested`). Investments are neither income nor expense: net stays income − expenses, but the cash balance uses `Transaction.signedCashAmount`, so contributions lower it and returns raise it.

### Default Categories (seeded on first launch)

**Expense**: Business, Utilities, Food, Groceries, Transport, Technology, Personal  
**Income**: Salary, Side Hustle  
**Investment**: Investments

All default categories have `isSystem = true` and appropriate SF Symbol icons + colors.

## How to Run

```bash
make install   # install SwiftFormat
make build     # format + build
make run       # format + build + launch
make format    # format all Swift files
make clean     # clean build artifacts
```

## Implementation Rules

1. Run `swiftformat .` before every build — code must compile without warnings or errors.
2. All SwiftUI views use `@Environment(\.modelContext)` for SwiftData access.
3. Use `@Query` macro for fetches; use `@Environment(\.dismiss)` for sheet dismissal.
4. Do NOT add explanatory comments to code unless the task explicitly requires it.
5. Follow existing patterns in the codebase. If a file already exists, read it first before editing.
6. Each phase builds on the previous one. Do not skip ahead.
7. After completing each phase, append the implementation guide to the phase file's end.
8. Keep views lean; extract reusable sub-views and helpers.
9. Use `Binding` and `@State` for local UI state; use `@Observable` classes for shared state.

## Immutability Rule

Transactions in any month **before** the current month are immutable:
- Edit and Delete actions are disabled in the context menu.
- Rows are visually dimmed (lower opacity).
- The current month's transactions are fully mutable until the month ends.

## Color / Styling Conventions

- Income items: green tint (`+`) prefix, green text highlight.
- Expense items: red tint (`−`) prefix.
- Investment items: amber (`Color.investment`), `−` for contributions and `+` for returns.
- Over-limit expense items: stronger red background/badge.
- Summary header: git-diff style — `+$X` in green, `−$Y` in red, net in bold black/white.
- Chart bars: one color per category, using the category's stored `colorHex`.

## Navigation / View Hierarchy

```
MenuBarExtra (macOS, toggled by "Show in menu bar" in Settings)
└── MenuBarView (month totals, over-budget list, recent items, goals, quick actions,
    Claude Code access toggle + copy setup command)

ContentView
├── MonthlyHeaderView
│   ├── MonthPicker (dropdown)
│   ├── AnalyticsButton (chart icon -> AnalyticsView)
│   ├── HelpButton (questionmark icon -> HelpView sheet)
│   └── SettingsButton (gear icon -> SettingsView sheet)
├── WeeklyChartView (summary tiles + goals strip + line chart with a "Same scale" toggle)
├── TransactionListView
│   ├── TransactionRowView (per item)
│   │   └── ContextMenu: Edit, Copy, Show Similar (-> SimilarTransactionsView sheet), Delete
│   └── AddButton (floating +, bottom right -> TransactionFormView sheet)
└── (Sheets / Windows)
    ├── TransactionFormView (add/edit; when adding, typing a title suggests frequent past transactions)
    ├── AnalyticsView (macOS: separate window, iOS: sheet; summary, insights and the
    │   │   main chart are always visible, lower content is switched by a dropdown
    │   │   picker in the toolbar)
    │   ├── Filters (range, granularity, income/expense toggles, amounts, categories) — shared across tabs
    │   ├── Always on top: summary header, insights cards, stacked bar chart
    │   ├── Transactions tab: transaction breakdown list
    │   ├── Categories tab: category stats breakdown
    │   ├── Balance & Heatmap tab: cumulative balance line + daily/weekly heatmap
    │   ├── Forecast & Budgets tab: end-of-month projection + budget board
    │   ├── Comparison & Recurring tab: month-vs-month table + committed/discretionary donut
    │   ├── Spend Patterns tab: weekday chart + size histogram
    │   ├── Repeat Spending tab: same-named expenses occurring 2+ times in the range
    │   │   (RepeatSpendingSection), tap a group -> SimilarTransactionsView sheet
    │   ├── Investments tab: contributed/returned/net tiles, contributions vs returns bars,
    │   │   net-invested-over-time line, per-holding breakdown (InvestmentsSection)
    │   ├── Goals tab: per-goal card with progress, pace, projection and cumulative chart
    │   │   (GoalsSection; ignores the filters; deep link idiot://goals)
    │   └── iOS toolbar wraps into two stacked rows (filters + range, tab + granularity)
    └── SettingsView
        ├── CategoryEditView (per category; "Budget alerts" switch for expense categories with a limit)
        ├── NotificationSettingsSection (budget alerts + warning threshold, recurring reminders + time; per device)
        ├── RecurringListView + RecurringFormView
        ├── SavingsGoalListView + SavingsGoalFormView (reorder, archive, delete)
        ├── CSVImportView (Import from CSV… -> review sheet, optional "Categorize with Apple
        │   Intelligence" button) + CSVExportView (Export to CSV…)
        ├── Auto-Categorization toggle + RecategorizeView (Re-categorize this month… -> review sheet)
        └── TrendChartView (spending habits line chart)

Widgets (IdiotWidgets extension)
├── Monthly Spending (total, segmented category bar, legend, + -> add form)
├── Recent Transactions (spent total, slim bar, latest rows)
├── Quick Log (frequent transactions as one-tap buttons, + -> add form)
├── Savings Goals, New Transaction
└── Control Center: Log Transaction (iOS 18+)

Shortcuts / Siri (App Intents)
└── Log Expense, Log Income, Month Summary, Add Transaction, Create Recurring Rule, Edit Transaction
```

## Analytics Engine

`Helpers/AnalyticsEngine.swift` holds pure, static computations fed pre-filtered `[Transaction]` arrays (no duplicated `@Query` work inside sections). Sections in `Views/` take computed value props from `AnalyticsView`. Recurring spend is identified via `Transaction.recurringRuleID != nil`; rule cost is normalized to monthly via `RecurringRule.monthlyNormalizedCost`. Forecasts use current-month pace plus upcoming occurrences computed by `AnalyticsEngine.upcomingOccurrences`.

## Widgets and App Intents

Widgets never open the store: they read the JSON `WidgetSnapshot` that `WidgetSnapshotWriter.write` puts in app-group defaults (the struct is duplicated in the app and the widget target; new fields must be optional). The Quick Log widget's buttons run `QuickLogIntent` inside the extension, which appends to `QuickLogQueue` and updates the snapshot optimistically; `QuickLogDrainer` in the app turns the queue into transactions (launch, becoming active, every snapshot write). App Intents in `idiot/Intents/` run in the app process on `AppModelContainer.shared.mainContext` and finish with `IntentData.commit()`. Edits through intents respect the "lock past months" setting. Widget kind strings must not change.


macOS only. `MCPHTTPServer` serves Streamable HTTP on `127.0.0.1:47821` from inside the app, and `MCPTools` runs on `container.mainContext` so changes reach the UI and CloudKit normally. Do not open the store from a separate process. Access is off by default and requires a bearer token kept in the keychain; write tools need a second toggle and always refuse past months. Claude Code connects with the `claude mcp add --transport http` command from `MCPServerController.claudeCodeCommand`, copyable from Settings or the menu bar.

## Phases (located in `phases/`)

| # | Phase File | Description |
|---|-----------|-------------|
| 1 | `01-setup.md` | Project setup, tooling, Makefile, directory structure, helpers |
| 2 | `02-models.md` | SwiftData models (Category, Transaction, CategoryType), seed data |
| 3 | `03-settings.md` | Settings sheet, category list, add/edit/delete categories |
| 4 | `04-transaction-list.md` | Transaction list with +/- prefix, floating add button |
| 5 | `05-add-edit-form.md` | Add/edit transaction form with validation |
| 6 | `06-context-menu.md` | Right-click menu (Edit/Copy/Delete), immutability for past months |
| 7 | `07-month-header.md` | Month picker, settings gear, summary bar (git diff style) |
| 8 | `08-bar-chart.md` | Weekly stacked bar chart with Swift Charts |
| 9 | `09-limits-highlighting.md` | Category budget limits, over-limit highlighting, profit/spend tinting |
| 10 | `10-trend-chart-polish.md` | Multi-month trend line chart, empty/error states, animations, a11y |
| 11 | `11-subscriptions-ios-polish.md` | Subscriptions, iOS support, widgets, iCloud sync |
| 12 | `12-analytics-expansion.md` | Analytics suite expansion (insights, balance, heatmap, forecast, comparison, recurring split, patterns) |
| 13 | `13-agent-access.md` | Local MCP server for agents such as Hermes |
| 14 | `14-csv-import.md` | Import bank statement CSVs with a review/edit step, simple CSV export |
| 15 | `15-search.md` | Search the selected month's transactions by title, description, category or amount |
| 16 | `16-frequent-similar.md` | Frequent-transaction suggestions in the add form, similar transactions sheet, Repeat Spending analytics tab |
| 17 | `17-auto-categorization.md` | On-device Apple Intelligence category suggestions (add form, CSV import, bulk re-categorize) |
| 18 | `18-sub-category.md` | Optional sub category label on transactions, main / sub / either category matching in filters, CSV and MCP support |
| 19 | `19-receipts.md` | Receipt attachments (files, photos, scanner, paste) with Vision OCR suggestions for amount, title and date |
| 20 | `20-savings-goals.md` | Savings goals linked to a category: Settings, main strip, Analytics tab, menu bar, Savings Goals widget |
| 21 | `21-notifications.md` | Local notifications: budget threshold alerts and day-before recurring reminders, per-device settings |
| 22 | `22-intents-widgets.md` | App Intents (log, summary, edit, recurring rule, open add form), spending-bar widgets, Quick Log widget, Control Center button |

## Quick Reference

| Aspect | Decision |
|--------|----------|
| Persistence | SwiftData (`@Model`, `ModelContainer`) |
| Charts | Apple Swift Charts framework |
| Settings | Modal sheet from gear icon |
| Analytics | Separate window (macOS) / sheet (iOS), opened from chart icon |
| Trend chart | Inside Settings area |
| Min macOS | 14.0 |
| Min iOS | 17.0 |
| Formatting | `swiftformat .` |
| Build | `xcodebuild` via Makefile |
