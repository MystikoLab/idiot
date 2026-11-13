# Phase 14 — CSV Import

Add transactions from bank statement CSVs without touching existing data.

## Implementation guide

- **Parser** (`Helpers/CSVImporter.swift`): RFC 4180-style tokenizer (quoted fields, escaped quotes, CRLF, BOM). Scans every record for a header row with a date column plus either an amount column (`Amount`, `Money in/out`, `Value`) or debit/credit columns, so multi-section statements such as Revolut's consolidated export work. A section ends at the first row whose date does not parse (e.g. `Total`). Rows whose `State`/`Status` is reverted, declined, failed or cancelled are skipped, as are zero amounts. Amounts accept currency prefixes (`S$`), thousands separators, decimal commas, and `-` or parentheses for negatives.
- **Review** (`Views/CSVImportView.swift`): sheet listing one editable draft per row (include toggle, title, amount, date, category, investment direction). Category suggestions come from the most recent existing transaction with the same title, then a category named like the statement's category column, then the first income or expense category by sign. Rows matching an existing transaction on the same day and amount are flagged as possible duplicates and unchecked by default.
- **Save**: only checked rows are inserted; nothing existing is modified or deleted. A renamed row keeps the statement text in `desc`.
- **Entry point**: Settings > Import > "Import from CSV…" (`fileImporter`, then the review sheet).

## Export

- **Writer** (`Helpers/CSVExporter.swift`): the given transactions, oldest first, as `Date,Title,Description,Category,Type,Amount`. Dates are `yyyy-MM-dd`; `Type` is Income, Expense, Investment or Investment Return; `Amount` is `signedCashAmount` (inflows positive, outflows negative). Fields with commas, quotes or newlines are quoted. The output re-imports cleanly through `CSVImporter`, and the category column matches existing categories by name.
- **Export page** (`Views/CSVExportView.swift`): sheet with a date range (This Month, Last Month, This Year and All Time presets plus From/To pickers, both days inclusive) and per-category checkboxes grouped by type, each showing its count in the range. A summary shows the count and money in/out for the selection; the file is named `idiot-transactions-<from>-to-<to>.csv`. On iOS the toolbar has a "Share N" `ShareLink` backed by `CSVFile` (`Transferable`, writes a temp file) so the share sheet offers Save to Files, AirDrop, Mail, etc. On macOS it is an "Export N" button that opens `fileExporter` with `CSVDocument`.
- **Entry point**: Settings > Import & Export > "Export to CSV…" opens the export page.
