#if os(macOS)
    import AppKit
    import SwiftData
    import SwiftUI

    struct MenuBarView: View {
        @Environment(\.openWindow) private var openWindow
        @Environment(\.openURL) private var openURL
        @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
        @Bindable private var controller = MCPServerController.shared
        @State private var copiedClaudeCommand = false

        private var monthTransactions: [Transaction] {
            let start = Date.now.startOfMonth
            return allTransactions.filter { $0.date >= start && $0.date <= Date.now.endOfMonth }
        }

        private var income: Double {
            total(of: .income)
        }

        private var expenses: Double {
            total(of: .expense)
        }

        private var net: Double {
            income - expenses
        }

        private var balance: Double {
            allTransactions.reduce(OpeningBalance.amount) { $0 + $1.signedCashAmount }
        }

        private var overLimitCategories: [(category: Category, spent: Double)] {
            Dictionary(grouping: monthTransactions.filter { $0.category?.type == .expense }) { $0.category }
                .compactMap { category, transactions -> (Category, Double)? in
                    guard let category, let limit = category.limit, limit > 0 else { return nil }
                    let spent = transactions.reduce(0) { $0 + $1.amount }
                    return spent > limit ? (category, spent) : nil
                }
                .sorted { $0.1 > $1.1 }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                summary
                if !overLimitCategories.isEmpty {
                    overLimitList
                }
                recentList
                Divider()
                actions
                Divider()
                claudeSection
                Divider()
                Button("Quit Idiot") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 300)
        }

        private var summary: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                HStack(spacing: 12) {
                    Text("+\(income.formattedCurrency)")
                        .foregroundStyle(.green)
                    Text("−\(expenses.formattedCurrency)")
                        .foregroundStyle(.red)
                    Text("= \(signed(net))")
                        .fontWeight(.bold)
                        .foregroundStyle(color(for: net))
                }
                .font(.callout.monospacedDigit())
                Text("Balance: \(signed(balance))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }

        private var overLimitList: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Over budget")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                ForEach(overLimitCategories, id: \.category.id) { entry in
                    HStack {
                        Label(entry.category.name, systemImage: entry.category.iconName)
                        Spacer()
                        Text("\(entry.spent.formattedCurrency) / \((entry.category.limit ?? 0).formattedCurrency)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }

        private var recentList: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if monthTransactions.isEmpty {
                    Text("No transactions this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(monthTransactions.prefix(4)) { transaction in
                    HStack {
                        Text(transaction.title)
                            .lineLimit(1)
                        Spacer()
                        Text(transaction.signedCashAmount >= 0 ? "+\(transaction.amount.formattedCurrency)" : "−\(transaction.amount.formattedCurrency)")
                            .monospacedDigit()
                            .foregroundStyle(amountColor(for: transaction))
                    }
                    .font(.caption)
                }
            }
        }

        private var actions: some View {
            VStack(alignment: .leading, spacing: 8) {
                menuButton("Add Transaction", systemImage: "plus.circle") {
                    activate()
                    if let url = URL(string: "idiot://add") {
                        openURL(url)
                    }
                }
                menuButton("Open Idiot", systemImage: "macwindow") {
                    showMainWindow()
                }
                menuButton("Analytics", systemImage: "chart.bar.xaxis") {
                    activate()
                    openWindow(id: "analytics")
                }
            }
        }

        private var claudeSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Claude Code access", isOn: $controller.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if controller.isEnabled {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    menuButton(copiedClaudeCommand ? "Copied — paste in Terminal" : "Copy Claude Code Setup Command", systemImage: "terminal") {
                        guard let command = controller.claudeCodeCommand else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copiedClaudeCommand = true
                    }
                }
            }
        }

        private var statusText: String {
            switch controller.status {
            case .off: "Off"
            case .starting: "Starting…"
            case .running:
                if let call = controller.lastToolCall {
                    "Running · last request \(call.name) at \(call.date.formatted(date: .omitted, time: .shortened))"
                } else {
                    "Running · ask Claude about your finances"
                }
            case let .failed(message): message
            }
        }

        private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private func showMainWindow() {
            activate()
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
        }

        private func activate() {
            NSApp.activate(ignoringOtherApps: true)
        }

        private func total(of type: CategoryType) -> Double {
            monthTransactions
                .filter { $0.category?.type == type }
                .reduce(0) { $0 + $1.amount }
        }

        private func signed(_ value: Double) -> String {
            let prefix = value > 0 ? "+" : value < 0 ? "−" : ""
            return "\(prefix)\(abs(value).formattedCurrency)"
        }

        private func color(for value: Double) -> Color {
            value > 0 ? .green : value < 0 ? .red : .primary
        }

        private func amountColor(for transaction: Transaction) -> Color {
            if transaction.isInvestment {
                return .investment
            }
            return transaction.category?.type == .income ? .green : .red
        }
    }
#endif
