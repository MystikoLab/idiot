# Phase 21 — Local notifications

Budget alerts when a category passes its warning level or its full monthly limit, and a heads-up the day before a recurring rule is due. Everything is local (`UserNotifications`); there is no push and no server.

## Implementation guide

- **Settings keys** (`NotificationSettings` in `Helpers/NotificationManager.swift`, plain `UserDefaults` / `@AppStorage`, per device, not synced): `notifyBudgetAlerts` (off), `notifyRecurringReminders` (off), `budgetWarningThreshold` (percent, 50–95, default 80), `recurringReminderMinutes` (minutes after midnight, default 540 = 09:00). Internal bookkeeping: `budgetAlertRecord` (thresholds already handled this month) and `recurringReminderIDs` (identifiers of the reminders currently scheduled).
- **Manager** (`Helpers/NotificationManager.swift`): `NotificationManager.shared`, an `@Observable` `NSObject` that is the `UNUserNotificationCenterDelegate` (banner + list + sound while the app is open; a tap only activates the app). `configure(container:)` is called once from `idiotApp.init` and reads through `container.mainContext`.
- **Triggers**: `refresh()` is debounced (0.6 s) and runs budget evaluation followed by reminder scheduling. It is called at launch, when the app becomes active, on `ModelContext.didSave`, from `WidgetSnapshotWriter.write` (so every place that refreshes the widget also evaluates budgets), when a CloudKit import finishes without error (`CloudSyncMonitor`), and after saving a category, saving a recurring rule or deleting one.
- **Budget alerts**: only the current month. `budgetStatuses` sums expense transactions by primary category for categories with `limit > 0`. `budgetDecision` (pure, static) returns the alerts to send and the record keys to mark:
  - at or above 100%: send "over" unless already recorded, and mark both "over" and "warning" (a jump straight past 100% sends one alert);
  - at or above the warning threshold: send "warning" unless already recorded.
  - Record keys are `yyyy-MM|<category id>|<warning or over>`; keys from other months are pruned on every pass. Keys are never removed within the month, so dropping below a threshold and crossing it again does not alert twice.
  - Categories with `budgetAlertsEnabled == false` are marked without alerting, so unmuting does not alert for something already crossed.
  - Turning the switch on or changing the threshold runs one silent pass (`budgetSettingsChanged`), which marks whatever is already crossed without alerting.
  - Bodies: "Food is at 82% of its $500.00 budget — $90.00 left for 12 days." / "Food is over its $500.00 budget by $35.00." / "Food has reached its $500.00 budget." (`formattedCurrency`).
- **Recurring reminders**: every refresh removes the previously scheduled identifiers and schedules `UNCalendarNotificationTrigger` requests for `AnalyticsEngine.upcomingOccurrences` in the next 60 days, capped at 40 (earliest first), so they fire when the app is not running. Fire time is the day before the occurrence at the chosen time; fire times in the past are skipped. Paused and ended rules, rules without a category and zero amounts are skipped by `upcomingOccurrences`. Wording: income "Salary — $4,000.00 arrives tomorrow", expense and investment "Netflix — $15.99 is due tomorrow". Identifiers start with `recurring-`.
- **Settings UI** (`Views/NotificationSettingsSection.swift`, placed after Auto-Categorization): "Budget alerts" switch with a "Warn at" stepper (steps of 5), "Recurring reminders" switch with a "Remind at" time picker. Turning a switch on requests authorization and only stays on when granted. When the system permission is denied both switches show off, with a note and an "Open Notification Settings" button. Turning a switch off removes the pending requests of that kind.
- **Category editor** (`Views/CategoryEditView.swift`): "Budget alerts" switch, shown for expense categories with a limit above zero.
- **Entitlements / Info.plist**: nothing added; local notifications need neither on macOS nor iOS.
- No cross-device dedupe: each device with the switch on alerts when it sees the crossing, including after an iCloud import while the app is running.
- Out of scope: App Intents, widgets, MCP, CSV, deep links from notifications.

## Migration

There is no `VersionedSchema`; the store relies on SwiftData's automatic lightweight migration and CloudKit's additive-only rules. This change only adds:

- One attribute, `Category.budgetAlertsEnabled: Bool = true`. Existing rows migrate with the default and nothing is rewritten.
- In CloudKit this is one new field (`CD_budgetAlertsEnabled`) on `CD_Category`. Deploy it from the development schema to production in the CloudKit Console before a release build reaches users. Older app versions ignore the field and keep syncing.
- `RecurringRule` is unchanged. All notification settings and the dedupe record live in `UserDefaults` on each device.
