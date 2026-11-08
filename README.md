# idiot

A fully native, 100% free and open source (FOSS) finance tracker for macOS and iOS.

Track income and expenses across customizable categories, visualize spending with Swift Charts, enforce category budgets, manage recurring transactions, and sync everything privately through iCloud.

## Highlights

- **Native** — Built entirely with SwiftUI + SwiftData + Swift Charts. No Electron, no web views, no tracking.
- **FOSS** — 100% open source. No ads, no accounts, no telemetry, no data collection.
- **Income + Expense tracking** — Log both sides of your money with per-category colors and icons.
- **Budget limits** — Set monthly spending caps per expense category, with over-limit highlighting.
- **Swift Charts analytics** — Weekly stacked bar charts, multi-month trend lines, and a full analytics suite: insights, cumulative balance, daily/weekly heatmap, end-of-month forecast, month-vs-month comparison, recurring vs. discretionary spend split, and spend-pattern breakdowns (weekday chart + size histogram).
- **Recurring transactions** — Define rules (subscriptions, rent, salary) that auto-detect upcoming occurrences.
- **iCloud sync** — CloudKit-backed SwiftData sync between your Mac and iPhone.
- **Widgets** — Home screen widgets via `WidgetSnapshotWriter` snapshots.
- **Past-month immutability** — Transactions in past months are locked from editing; the current month stays fully editable.
- **Git-diff-style summary** — Monthly header shows `+$X` in green, `−$Y` in red, with bold net.
- **Agent access (optional, macOS)** — A local MCP server lets agents such as Hermes query your finances. Off by default.

## Requirements

| | |
|---|---|
| macOS | 14.0+ |
| iOS | 17.0+ |
| Xcode | 26.5+ |
| SwiftFormat | 0.55.5 (installed automatically via `make install`) |

## Build & Run

```bash
make install   # install SwiftFormat
make build     # format + build (macOS)
make run       # format + build + launch the app
make install-release  # signed Release build with iCloud, installed to /Applications
make build-ios # build for iOS Simulator (iPhone 17 Pro)
make run-ios   # build + install + launch on the simulator
make run-device DEVICE_NAME="iPhone"  # build + install on a physical iPhone
make clean     # remove build artifacts
```

## Agent Access (MCP)

The Mac app can serve your finances to a local AI agent over MCP (Streamable HTTP). It is off by default, listens only on `127.0.0.1:47821`, needs a bearer token, and runs only while the app is open. Data from your iPhone is available once it has synced through iCloud.

To connect [Hermes](https://github.com/NousResearch/hermes-agent):

1. Turn on **Settings > Agent Access (MCP) > Allow agent access**.
2. Use **Copy Hermes Config** and paste the result into `~/.hermes/config.yaml`.
3. Use **Copy Access Token** and paste the result into `~/.hermes/.env`.
4. Run `/reload-mcp` in Hermes. Also run it after changing the write toggle, because the tool list is read when Hermes connects.

Read tools: `get_month_summary`, `list_transactions`, `list_categories`, `list_recurring_rules`, `get_spending_trend`, `get_forecast`.

Write tools, available only with **Allow agents to change transactions** on: `add_transaction`, `update_transaction`, `delete_transaction`. Past months are always locked for agents, even if the app's lock setting is off. The `trust: untrusted` line in the config makes Hermes ask for approval before each write.

Anything an agent reads is sent to the AI model it is configured to use.

## Tech Stack

- **SwiftUI** — declarative UI for both macOS and iOS
- **SwiftData** — local persistence with CloudKit (iCloud) sync
- **Swift Charts** — all visualizations
- **SwiftFormat** — enforced formatting on every build (`swiftformat .`)

## Project Structure

```
idiot/
├── Models/          # SwiftData models (Transaction, Category, RecurringRule, ...)
├── ViewModels/      # CloudSyncMonitor
├── Views/           # SwiftUI views (list, forms, charts, analytics, settings)
├── Helpers/         # Pure logic: AnalyticsEngine, RecurringEngine, formatters, extensions
└── phases/          # Development phase documents
```

## License

This project is free software: you can redistribute it and/or modify it under the terms of your choice of open source license. See [LICENSE](LICENSE) for details.
