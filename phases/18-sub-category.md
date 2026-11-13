# Phase 18 — Main Category + Sub Category

Every transaction keeps its category (the main category) and can carry an optional sub category. The sub category is a second label only: the full amount, the type, budgets, charts, totals and analytics all stay with the main category. Amounts are never split.

## Implementation guide

- **Models**: `Transaction.subCategory: Category?` and its inverse `Category.subTransactions: [Transaction]?` (`deleteRule: .nullify`). Deleting a category still cascades to the transactions it is the main category of, but only clears it where it was a sub category. `RecurringRule` has no sub category.
- **Match mode** (`Helpers/CategoryMatchMode.swift`): `main`, `sub`, `either`, with `categories(of:)` and `matches(_:where:)`. Shared by the list filter, analytics and the MCP `category_match` argument.
- **Form** (`Views/TransactionFormView.swift`): a "Sub category" picker under the category picker, default "None", listing every category except the selected main one. Changing the main category to the current sub clears the sub. The sub is stored in the draft (`subCategoryID`), copied when a title suggestion is picked, and saved on add and edit.
- **List** (`Views/TransactionListView.swift`): rows are unchanged and show only the main category. The filter popover has a "Match categories by" menu stored in `@AppStorage("filterCategoryMatchMode")`, default Either. While any category is unchecked, a transaction is shown when one of the categories the mode looks at is still checked (in Main mode a transaction without a category is shown, as before). The same mode decides which category names the search text is compared with. The Income / Expense / Investment toggles always use the main category's type. "Copy" carries the sub category over.
- **Analytics** (`Views/AnalyticsView.swift`): the same menu above the category toggles, stored in `@AppStorage("analyticsCategoryMatchMode")`, default Either. It only decides which transactions pass the category filter (`isInSelectedCategories`); every total, chart and breakdown still groups by main category.
- **CSV**: the export has a "Sub Category" column after "Category", empty when there is none; the export category filter matches the main category. The importer reads a `sub category` / `subcategory` / `sub-category` / `sub_category` column into `Row.sourceSubCategory`, and the review resolves it by case-insensitive category name into `ImportDraft.subCategory`. Unknown names are ignored, a sub equal to the row's final main category is dropped on import, and files without the column behave as before.
- **MCP** (`Helpers/MCPTools.swift`): transactions are returned with `sub_category`. `add_transaction` and `update_transaction` accept `sub_category` (name or id, resolved like `category`); on update an empty string clears it. A sub equal to the main category is rejected, and changing the main category to the existing sub clears the sub. `list_transactions` has `category_match` (`main` / `sub` / `either`, default `main`) for its `category` filter.
- Not covered on purpose: `SimilarTransactionsView`, auto-categorization, recurring rules and widgets.

## Migration

There is no `VersionedSchema` or migration plan; the store relies on SwiftData's automatic lightweight migration and on CloudKit's additive-only schema rules. This change satisfies both:

- It only adds: one optional to-one relationship (`Transaction.subCategory`) and one optional to-many relationship (`Category.subTransactions`). Nothing is renamed, removed or retyped, and `Transaction.category` keeps its name and its existing inverse.
- Both new properties are optional with no default needed, so existing rows migrate with `subCategory == nil` and no data has to be rewritten.
- No unique constraints are added, and the new relationship has an explicit inverse and is optional on both sides, which CloudKit requires of every relationship.
- In CloudKit the change is one new reference field on the existing `CD_Transaction` record type. Adding fields is allowed in the production schema; devices still on the old version ignore the field and keep syncing.
- The delete rule is `.nullify`, so the new relationship can never remove a transaction.

Before a release build reaches users, the new field has to be deployed from the CloudKit development schema to production (CloudKit Console > Deploy Schema Changes), as for any earlier model addition.
