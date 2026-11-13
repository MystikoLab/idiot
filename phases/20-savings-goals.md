# Phase 20 — Savings goals

A goal has a name, a target amount, a start date, an optional deadline and a linked category ("Japan trip, $3,000 by June"). Progress is the money logged in the linked category from the start date onward.

## Implementation guide

- **Model** (`Models/SavingsGoal.swift`): `SavingsGoal` with `id`, `name`, `targetAmount`, `startDate`, `deadline?`, `iconName`, `colorHex`, `sortOrder`, `isArchived`, `createdAt`, `syncStamp`, `category: Category?`. `Category.goals: [SavingsGoal]?` is the inverse with delete rule `.nullify`, so deleting a category keeps the goal ("No category linked", zero progress). `[SavingsGoal].activeOrdered` / `.archivedOrdered` give the display order (`sortOrder`, then `createdAt`). `SavingsGoal.self` is registered in the single `ModelContainer` in `idiotApp.swift`; "Erase All Data" deletes goals and Force Push touches their `syncStamp`.
- **Math** (`Helpers/GoalEngine.swift`): pure static functions over the goal's values and `[Transaction]`.
  - Counted transactions: primary `category` equals the linked category (sub-categories are not counted) and `date >= startOfDay(startDate)`. Investment categories contribute `investedAmount` (contributions − returns), income and expense categories contribute `amount`.
  - `status`: `reached` when saved ≥ target; `open` ("In progress") without a deadline; otherwise `onTrack` when saved ≥ the linear pace between start date and deadline at "now", else `behind` (also once the deadline has passed).
  - `requiredMonthly`: remaining ÷ months until the deadline (a month is 30.4375 days, at least one month); `nil` without a deadline, when reached, or after the deadline.
  - `projectedCompletion`: now + remaining ÷ average monthly saving since the start date (elapsed time counted as at least one month); `nil` ("—") when nothing is saved yet, on the first day, or when reached.
  - `cumulativeSeries`: one point per day with activity, starting at zero on the start date and extended to "now".
  - `GoalEngine.progress(for:)` / `series(for:)` read `goal.category?.transactions` and return the `Progress` value / series every surface uses.
- **Shared views** (`Views/GoalStatusBadge.swift`): status color and icon, `GoalStatusBadge`, `GoalIcon`, and `Progress.amountText` / `tint` / `paceText` ("Save $X/month to hit it by <date>").
- **Settings** (`Views/SavingsGoalListView.swift`, `Views/SavingsGoalFormView.swift`): Settings > Savings Goals lists active goals (drag to reorder, `EditButton` on iOS, context menu and swipe for Edit / Archive / Delete) and an "Archived" group (Unarchive / Delete). The form edits name, target, linked category (any type or None, plus "Create investment category “<name>”" which inserts an investment category with the goal's color and icon and selects it), start date, optional deadline, color and icon. Dates are stored at start of day.
- **Main screen** (`Views/GoalsStripView.swift`, inserted under the summary tiles in `WeeklyChartView`): up to 3 goals on macOS / 2 on iOS with name, status, slim bar and "$saved of $target" (masked by `maskedAmount()`), hidden with no active goals. The "Goals +N more ›" header opens `idiot://goals`.
- **Analytics** (`Views/GoalsSection.swift`, `Views/GoalCardView.swift`): new `AnalyticsTab.goals`. One card per active goal with progress bar, saved / target / remaining, needed monthly, projected completion, and a step line chart of cumulative progress with a dashed target rule and a dashed pace line when there is a deadline. The tab ignores the Analytics filters and says so in a caption.
- **Deep link**: `idiot://goals` (handled in `ContentView.onOpenURL`) stores the tab in the `analyticsRequestedTab` default (`AnalyticsView.requestedTabKey`) and opens Analytics; `AnalyticsView` applies and clears it on appear / change, which also works when the macOS Analytics window is already open.
- **Menu bar** (`Views/MenuBarView.swift`): a "Goals" list (name, percent, small bar; first 4) under "Recent", hidden with no active goals.
- **Widget**: `WidgetSnapshot.goals: [SnapshotGoal]?` (first 5 active goals: `id`, `name`, `saved`, `target`, `status` raw value of `GoalEngine.Status`, `deadline?`, `colorHex`, `iconName`). The struct is duplicated in `Helpers/WidgetSnapshotWriter.swift` (app) and `IdiotWidgets/WidgetSnapshot.swift` (widget); keep both in sync. The field is optional because synthesized `Decodable` rejects a missing non-optional key, so snapshots stored by older builds still decode. `SavingsGoalsWidget` (kind `SavingsGoalsWidget`, in `IdiotWidgets/Widgets.swift`, registered in the bundle): systemSmall shows the first goal with a ring, systemMedium up to 3 goals with bars; it opens `idiot://goals`. Goal add / edit / reorder / archive / delete rewrite the snapshot, in addition to the existing transaction-driven writes.
- Out of scope: notifications, App Intents, CSV, MCP.

## Migration

There is no `VersionedSchema`; the store relies on SwiftData's automatic lightweight migration and CloudKit's additive-only rules. This change only adds:

- A new entity `SavingsGoal` whose attributes are all defaulted or optional, with no unique constraints.
- One optional to-many relationship `Category.goals` with the explicit optional inverse `SavingsGoal.category` (delete rule `.nullify`). Existing categories migrate with no goals and nothing is rewritten.
- In CloudKit this is one new record type (`CD_SavingsGoal`). Deploy it from the development schema to production in the CloudKit Console before a release build reaches users. Older app versions ignore the new record type and keep syncing.
- The widget snapshot gains an optional `goals` key; old snapshots decode with `goals == nil` and older widget builds ignore the key.
