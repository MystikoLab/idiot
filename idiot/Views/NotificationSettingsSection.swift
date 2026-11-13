import SwiftUI

struct NotificationSettingsSection: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationSettings.budgetAlertsKey) private var budgetAlerts = false
    @AppStorage(NotificationSettings.recurringRemindersKey) private var recurringReminders = false
    @AppStorage(NotificationSettings.warningThresholdKey) private var warningThreshold = NotificationSettings.defaultWarningThreshold
    @AppStorage(NotificationSettings.reminderMinutesKey) private var reminderMinutes = NotificationSettings.defaultReminderMinutes
    private let manager = NotificationManager.shared

    private var budgetAlertsOn: Bool {
        budgetAlerts && !manager.isDenied
    }

    private var recurringRemindersOn: Bool {
        recurringReminders && !manager.isDenied
    }

    var body: some View {
        Section {
            Toggle("Budget alerts", isOn: budgetBinding)

            if budgetAlertsOn {
                Stepper(value: $warningThreshold, in: NotificationSettings.warningThresholdRange, step: 5) {
                    LabeledContent("Warn at") {
                        Text("\(warningThreshold)%")
                            .monospacedDigit()
                    }
                }
                .onChange(of: warningThreshold) {
                    manager.budgetSettingsChanged()
                }
            }

            Toggle("Recurring reminders", isOn: recurringBinding)

            if recurringRemindersOn {
                DatePicker("Remind at", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
            }

            if manager.isDenied {
                Text("Notifications are turned off for Idiot in system settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    if let url = NotificationManager.systemSettingsURL {
                        openURL(url)
                    }
                } label: {
                    Label("Open Notification Settings", systemImage: "bell.badge")
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Budget alerts tell you when a category passes the warning level or its full monthly limit. Recurring reminders arrive the day before a subscription or salary is due. These settings apply to this device only.")
        }
        .task {
            await manager.refreshAuthorization()
        }
    }

    private var budgetBinding: Binding<Bool> {
        Binding {
            budgetAlertsOn
        } set: { value in
            setEnabled(value) { enabled in
                budgetAlerts = enabled
                manager.budgetSettingsChanged()
            }
        }
    }

    private var recurringBinding: Binding<Bool> {
        Binding {
            recurringRemindersOn
        } set: { value in
            setEnabled(value) { enabled in
                recurringReminders = enabled
                manager.recurringSettingsChanged()
            }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            manager.recurringSettingsChanged()
        }
    }

    private func setEnabled(_ value: Bool, apply: @escaping (Bool) -> Void) {
        guard value else {
            apply(false)
            return
        }
        Task {
            let granted = await manager.requestAuthorization()
            apply(granted)
        }
    }
}
