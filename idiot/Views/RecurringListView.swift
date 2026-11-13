import SwiftData
import SwiftUI

struct RecurringListView: View {
    var type: CategoryType? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRule.title) private var rules: [RecurringRule]
    @State private var showAdd = false
    @State private var showAddModeChoice = false
    @State private var editingRule: RecurringRule?
    @State private var deletingRule: RecurringRule?

    private var showIncome: Bool {
        type != .expense
    }

    private var displayRules: [RecurringRule] {
        guard let type else { return rules.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
        return rules
            .filter { $0.category?.type == type }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var monthlyIncomeEstimate: Double {
        displayRules
            .filter(\.isActive)
            .filter { $0.category?.type == .income }
            .reduce(0) { $0 + $1.amount * $1.frequency.perMonthEstimateMultiplier }
    }

    private var monthlyExpenseEstimate: Double {
        displayRules
            .filter(\.isActive)
            .filter { $0.category?.type == .expense }
            .reduce(0) { $0 + $1.amount * $1.frequency.perMonthEstimateMultiplier }
    }

    private var activeCount: Int {
        displayRules.filter(\.isActive).count
    }

    private var navigationTitle: String {
        switch type {
        case .income: "Auto Salary"
        case .expense: "Subscriptions"
        case .investment: "Recurring Investments"
        case nil: "Recurring"
        }
    }

    var body: some View {
        List {
            Section {
                if displayRules.isEmpty {
                    emptyState
                } else {
                    ForEach(displayRules) { rule in
                        ruleRow(rule)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingRule = rule
                            }
                            .contextMenu {
                                Button("Edit") {
                                    editingRule = rule
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deletingRule = rule
                                } label: {
                                    Label("Delete Rule", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    deletingRule = rule
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text(type == .income ? "Auto Salary" : "Subscriptions")
                    Spacer()
                    Button {
                        handleAddTap()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(type == .income ? "Add Salary Rule" : "Add Subscription")
                }
            } footer: {
                if type == nil {
                    let incomeLabel = monthlyIncomeEstimate.formattedCurrency
                    let expenseLabel = monthlyExpenseEstimate.formattedCurrency
                    Text("\(incomeLabel) in · \(expenseLabel) out per month · \(activeCount) active")
                } else {
                    Text("\(monthlyExpenseEstimate.formattedCurrency) per month estimated · \(activeCount) active")
                }
            }
        }
        .navigationTitle(navigationTitle)
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        handleAddTap()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(type == .income ? "Add Salary Rule" : "Add Subscription")
                }
            }
        #endif
            .confirmationDialog("Add Recurring Rule", isPresented: $showAddModeChoice, titleVisibility: .visible) {
                Button("Add Subscription") {
                    addRule(mode: .subscription)
                }
                Button("Add Salary Rule") {
                    addRule(mode: .salary)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAdd) {
                RecurringFormView(mode: type == .income ? .salary : addMode)
            }
            .sheet(item: $editingRule) { rule in
                RecurringFormView(mode: rule.category?.type == .income ? .salary : .subscription, rule: rule)
            }
            .alert("Delete Rule?", isPresented: deleteBinding) {
                Button("Delete Rule Only", role: .destructive) {
                    deleteRule(keepPast: true)
                }
                Button("Delete Rule + Transactions", role: .destructive) {
                    deleteRule(keepPast: false)
                }
                Button("Cancel", role: .cancel) {
                    deletingRule = nil
                }
            } message: {
                Text("Past transactions already generated stay in your history unless you remove them.")
            }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private var deleteBinding: Binding<Bool> {
        Binding {
            deletingRule != nil
        } set: { isPresented in
            if !isPresented {
                deletingRule = nil
            }
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        let category = rule.category
        let next = RecurringEngine.nextDueDate(for: rule)

        return HStack(spacing: 12) {
            Image(systemName: category?.iconName ?? "repeat")
                .frame(width: 24)
                .foregroundStyle(Color(hex: category?.colorHex ?? "#8E8E93"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.title)
                        .fontWeight(.medium)
                    if !rule.isActive {
                        Text("Paused")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(rowSubtitle(rule, next: next))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText(rule))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(rule.category?.type == .income ? .green : .primary)
                Text(shortFrequency(rule.frequency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func amountText(_ rule: RecurringRule) -> String {
        let base = rule.amount.formattedCurrency
        return rule.category?.type == .income ? "+\(base)" : "−\(base)"
    }

    private func addRule(mode: RecurringFormView.Mode) {
        showAddModeChoice = false
        withAnimation {
            showAdd = true
        }
        addMode = mode
    }

    @State private var addMode: RecurringFormView.Mode = .subscription

    private func rowSubtitle(_ rule: RecurringRule, next: Date?) -> String {
        var parts: [String] = []
        if let next {
            let label = rule.frequency == .weekly ? "Next charge" : "Next due"
            parts.append("\(label): \(next.formatted(style: .medium))")
        } else {
            parts.append("Ended")
        }
        return parts.joined(separator: " · ")
    }

    private func shortFrequency(_ frequency: RecurrenceFrequency) -> String {
        switch frequency {
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        }
    }

    private func deleteRule(keepPast: Bool) {
        guard let rule = deletingRule else { return }
        if !keepPast {
            let ruleID = rule.id
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { tx in
                    tx.recurringRuleID == ruleID
                }
            )
            descriptor.fetchLimit = 1000
            if let generated = try? modelContext.fetch(descriptor) {
                generated.forEach(modelContext.delete)
            }
        }
        modelContext.delete(rule)
        deletingRule = nil
        NotificationManager.shared.refresh()
    }

    private func handleAddTap() {
        if type != nil {
            addMode = type == .income ? .salary : .subscription
            showAdd = true
        } else {
            showAddModeChoice = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ContentUnavailableView(
                type == .income ? "No income rules yet" : "No subscriptions yet",
                systemImage: "repeat",
                description: Text("Track recurring charges and income so they're logged automatically.")
            )

            Button("Add Rule") {
                handleAddTap()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}
