# AGENTS.md — Finance Tracker macOS + iOS App

## Project Overview

A macOS + iOS SwiftUI finance tracking app with SwiftData persistence. The app tracks both income and expense transactions across customizable categories, visualizes spending with Swift Charts (weekly income/expense/investment line chart (expense axis left, income axis right, investments on an unlabeled scale) + multi-month trend line charts + a full Analytics suite), enforces category budgets, supports recurring transaction rules, iCloud sync, widgets, and locks past-month data from editing.

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
│   ├── RecurrenceFrequency.swift
│   └── DefaultCategories.swift
├── ViewModels/
│   ├── CloudSyncMonitor.swift
│   └── MCPServerController.swift (macOS)
├── Views/
│   ├── TransactionListView.swift
│   ├── TransactionRowView.swift
│   ├── TransactionFormView.swift
│   ├── MCPSettingsSection.swift (macOS)
│   ├── MenuBarView.swift (macOS menu bar extra)
│   ├── HelpView.swift (help & savings guide, opened from header ? button or Settings)
│   ├── RecurringListView.swift
│   ├── RecurringFormView.swift
│   ├── SettingsView.swift
│   ├── CategoryEditView.swift
│   ├── MonthlyHeaderView.swift
│   ├── WeeklyChartView.swift
│   ├── SummaryBarView.swift
│   ├── TrendChartView.swift
│   └── AnalyticsView.swift (+ HeatmapSection, BalanceChartSection,
│        InsightsSection, ForecastSection, PeriodComparisonSection,
│        RecurringSplitSection, SpendPatternsSection, InvestmentsSection)
├── Helpers/
│   ├── DateExtensions.swift
│   ├── ColorExtensions.swift
│   ├── NumberFormatterExtensions.swift
│   ├── AnalyticsGranularity.swift
│   ├── AnalyticsEngine.swift
│   ├── RecurringEngine.swift
│   ├── WidgetSnapshotWriter.swift
│   ├── MCPTools.swift (macOS)
│   ├── MCPProtocol.swift (macOS)
│   └── MCPHTTPServer.swift (macOS)
├── Resources/
│   └── (Assets, etc.)
├── idiotApp.swift
└── ContentView.swift
```

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

**`Transaction`** — `@Model`
- `id: UUID`
- `title: String`
- `desc: String?`
- `amount: Double`
- `date: Date`
- `category: Category` (relationship)
- `createdAt: Date`
- `isInvestmentReturn: Bool` (investment categories only: `false` = contribution, `true` = return such as a sale or dividend)

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
└── MenuBarView (month totals, over-budget list, recent items, quick actions,
    Claude Code access toggle + copy setup command)

ContentView
├── MonthlyHeaderView
│   ├── MonthPicker (dropdown)
│   ├── AnalyticsButton (chart icon -> AnalyticsView)
│   ├── HelpButton (questionmark icon -> HelpView sheet)
│   └── SettingsButton (gear icon -> SettingsView sheet)
├── WeeklyChartView (summary tiles + line chart with a "Same scale" toggle)
├── TransactionListView
│   ├── TransactionRowView (per item)
│   │   └── ContextMenu: Edit, Copy, Delete
│   └── AddButton (floating +, bottom right -> TransactionFormView sheet)
└── (Sheets / Windows)
    ├── TransactionFormView (add/edit)
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
    │   ├── Investments tab: contributed/returned/net tiles, contributions vs returns bars,
    │   │   net-invested-over-time line, per-holding breakdown (InvestmentsSection)
    │   └── iOS toolbar wraps into two stacked rows (filters + range, tab + granularity)
    └── SettingsView
        ├── CategoryEditView (per category)
        ├── RecurringListView + RecurringFormView
        └── TrendChartView (spending habits line chart)
```

## Analytics Engine

`Helpers/AnalyticsEngine.swift` holds pure, static computations fed pre-filtered `[Transaction]` arrays (no duplicated `@Query` work inside sections). Sections in `Views/` take computed value props from `AnalyticsView`. Recurring spend is identified via `Transaction.recurringRuleID != nil`; rule cost is normalized to monthly via `RecurringRule.monthlyNormalizedCost`. Forecasts use current-month pace plus upcoming occurrences computed by `AnalyticsEngine.upcomingOccurrences`.

## Agent Access (MCP)

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
