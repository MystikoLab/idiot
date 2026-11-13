# Phase 15 — Search

Find transactions in the selected month from the main list.

## Implementation guide

- **State** (`ContentView.swift`): `searchText` is `@State` in `ContentView` and is passed down to `TransactionListView` as a plain `searchText: String` (through `MonthPageView` on iOS). It is not persisted and survives month changes.
- **Search field**: `.searchable(text:prompt:)` on the macOS `HSplitView` (window toolbar) and on the iOS paged `TabView` inside the `NavigationStack`, with `.navigationBarDrawer(displayMode: .always)` so the field stays visible under the navigation bar.
- **Matching** (`Views/TransactionListView.swift`): `popoverFilteredTransactions` holds the result of the filter popover; `filteredTransactions` applies the query on top of it, so counts, select-all, batch delete and Return-to-edit all respect the search. Title, description and category name use `localizedStandardContains` (case- and diacritic-insensitive). `amountSearchPrefix` strips whitespace, symbols (currency signs, `+`, `−`), `,`, `'` and `-` from the query; if only digits and at most one `.` remain, it is matched as a prefix of the amount formatted as `%.2f` (`42` matches 42.50 and 420.00, `42.5` matches 42.50).
- **Empty state**: `ContentUnavailableView.search(text:)` when the query hides every transaction the filters left; the existing "No transactions yet" state otherwise.
- **Selection**: when the query changes, selected rows that are no longer visible are deselected.
- The weekly chart and summary tiles are not affected by the search.
