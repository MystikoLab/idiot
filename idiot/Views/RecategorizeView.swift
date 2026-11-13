import SwiftData
import SwiftUI

struct RecategorizeProposal: Identifiable {
    let transaction: Transaction
    let current: Category
    let proposed: Category
    var isSelected = true

    var id: UUID {
        transaction.id
    }
}

struct RecategorizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var proposals: [RecategorizeProposal] = []
    @State private var isRunning = true
    @State private var wasStopped = false
    @State private var done = 0
    @State private var total = 0
    @State private var runTask: Task<Void, Never>?

    private var selectedCount: Int {
        proposals.filter(\.isSelected).count
    }

    var body: some View {
        NavigationStack {
            List {
                if isRunning {
                    progressSection
                }
                if !proposals.isEmpty {
                    Section {
                        ForEach($proposals) { $proposal in
                            RecategorizeRow(proposal: $proposal)
                        }
                    } header: {
                        Text("\(selectedCount) of \(proposals.count) selected")
                            .textCase(nil)
                    } footer: {
                        Text("Nothing changes until you choose Apply. Only checked rows are updated.")
                    }
                } else if !isRunning {
                    ContentUnavailableView(
                        "No Changes Suggested",
                        systemImage: "checkmark.seal",
                        description: Text(wasStopped
                            ? "Stopped before any change was found."
                            : "This month's transactions already match the suggested categories.")
                    )
                }
            }
            .navigationTitle("Re-categorize This Month")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Select All") { setSelected(true) }
                        Button("Select None") { setSelected(false) }
                    } label: {
                        Label("Selection", systemImage: "checklist")
                    }
                    .disabled(proposals.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply \(selectedCount)") {
                        apply()
                    }
                    .disabled(isRunning || selectedCount == 0)
                }
            }
            .onAppear {
                if runTask == nil {
                    start()
                }
            }
            .onDisappear {
                runTask?.cancel()
            }
            #if os(macOS)
            .frame(minWidth: 620, minHeight: 460)
            #endif
        }
    }

    private var progressSection: some View {
        Section {
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("\(done) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Stop") {
                    wasStopped = true
                    runTask?.cancel()
                }
            }
        } footer: {
            Text("Checking this month's transactions against your earlier history and on-device Apple Intelligence.")
        }
    }

    private func setSelected(_ value: Bool) {
        for index in proposals.indices {
            proposals[index].isSelected = value
        }
    }

    private func start() {
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let monthStart = Date.now.startOfMonth
        let history = AutoCategorizer.History(all.filter { $0.date < monthStart })
        let targets = all.filter { $0.date.isInCurrentMonth && $0.recurringRuleID == nil && $0.category != nil }
        let byID = Dictionary(targets.map { ($0.id, $0) }) { first, _ in first }

        let requests = targets.compactMap { transaction -> (id: UUID, request: AutoCategorizer.Request)? in
            guard let current = transaction.category else { return nil }
            let candidates = categories.filter { $0.type == current.type }
            guard candidates.count > 1 else { return nil }
            return (id: transaction.id, request: AutoCategorizer.Request(
                title: transaction.title,
                details: transaction.desc,
                amount: transaction.amount,
                candidates: candidates
            ))
        }
        total = requests.count

        runTask = Task {
            await AutoCategorizer.resolve(requests, history: history) { completed in
                done = completed
            } onResult: { id, proposed in
                guard let transaction = byID[id], let current = transaction.category, current.id != proposed.id else { return }
                proposals.append(RecategorizeProposal(transaction: transaction, current: current, proposed: proposed))
            }
            isRunning = false
        }
    }

    private func apply() {
        for proposal in proposals where proposal.isSelected {
            proposal.transaction.category = proposal.proposed
        }
        try? modelContext.save()
        WidgetSnapshotWriter.write(context: modelContext)
        dismiss()
    }
}

private struct RecategorizeRow: View {
    @Binding var proposal: RecategorizeProposal

    var body: some View {
        HStack(spacing: 10) {
            Button {
                proposal.isSelected.toggle()
            } label: {
                Image(systemName: proposal.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(proposal.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(proposal.isSelected ? "Selected" : "Not selected")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(proposal.transaction.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(proposal.transaction.amount.formattedCurrency)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    categoryLabel(proposal.current)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    categoryLabel(proposal.proposed)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .opacity(proposal.isSelected ? 1 : 0.5)
        .accessibilityElement(children: .combine)
    }

    private func categoryLabel(_ category: Category) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.iconName)
                .foregroundStyle(Color(hex: category.colorHex))
                .accessibilityHidden(true)
            Text(category.name)
        }
    }
}
