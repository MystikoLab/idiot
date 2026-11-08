import SwiftUI

#if os(macOS)
    struct MonthlyHeaderView: ToolbarContent {
        @Environment(\.openWindow) private var openWindow
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Binding var selectedMonth: Date
        @Binding var showAddTransaction: Bool
        @Binding var showSettings: Bool
        @Binding var showHelp: Bool

        private let syncMonitor = CloudSyncMonitor.shared

        private var isCurrentMonth: Bool {
            Calendar.current.isDate(selectedMonth, equalTo: Date.now.startOfMonth, toGranularity: .month)
        }

        private var recentMonths: [Date] {
            let calendar = Calendar.current
            let current = Date.now.startOfMonth
            return (0 ..< 12).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
        }

        private var syncIcon: String {
            if syncMonitor.showsError {
                return "exclamationmark.icloud"
            }
            return syncMonitor.activeEvent == nil ? "checkmark.icloud" : "arrow.clockwise.icloud"
        }

        var body: some ToolbarContent {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Label("Previous Month", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Previous month")

                Button {
                    moveMonth(by: 1)
                } label: {
                    Label("Next Month", systemImage: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Next month")

                Menu {
                    ForEach(recentMonths, id: \.self) { month in
                        Button {
                            setSelectedMonth(month)
                        } label: {
                            if month == selectedMonth {
                                Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "checkmark")
                            } else {
                                Text(month.formatted(.dateTime.month(.wide).year()))
                            }
                        }
                    }
                } label: {
                    Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.headline.monospacedDigit())
                }
                .accessibilityLabel("Selected month")

                if !isCurrentMonth {
                    Button("Today") {
                        setSelectedMonth(Date.now.startOfMonth)
                    }
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Jump to the current month")
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Spacer()

                Label("iCloud", systemImage: syncIcon)
                    .foregroundStyle(syncMonitor.showsError ? Color.red : Color.secondary)
                    .help("iCloud: \(syncMonitor.statusText)")
                    .accessibilityValue(syncMonitor.statusText)

                Button {
                    openWindow(id: "analytics")
                } label: {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .help("Open Analytics")

                Button {
                    showHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .help("Help and savings guide")

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")

                Button {
                    showAddTransaction = true
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add transaction (⌘N)")
            }
        }

        private func moveMonth(by value: Int) {
            guard let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
            setSelectedMonth(newDate)
        }

        private func setSelectedMonth(_ month: Date) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selectedMonth = month
            }
        }
    }
#endif
