import SwiftData
import SwiftUI

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.sortOrder) private var goals: [SavingsGoal]
    @State private var showAdd = false
    @State private var editingGoal: SavingsGoal?
    @State private var deletingGoal: SavingsGoal?

    private var activeGoals: [SavingsGoal] {
        goals.activeOrdered
    }

    private var archivedGoals: [SavingsGoal] {
        goals.archivedOrdered
    }

    var body: some View {
        List {
            Section {
                if activeGoals.isEmpty {
                    emptyState
                } else {
                    ForEach(activeGoals) { goal in
                        row(goal)
                    }
                    .onMove(perform: move)
                }
            } header: {
                HStack {
                    Text("Goals")
                    Spacer()
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add Goal")
                }
            } footer: {
                if activeGoals.count > 1 {
                    Text("Drag to reorder. The first goals are shown on the main screen, the menu bar and widgets.")
                }
            }

            if !archivedGoals.isEmpty {
                Section("Archived") {
                    ForEach(archivedGoals) { goal in
                        row(goal)
                    }
                }
            }
        }
        .navigationTitle("Savings Goals")
        #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Goal")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        #endif
            .sheet(isPresented: $showAdd) {
                SavingsGoalFormView()
            }
            .sheet(item: $editingGoal) { goal in
                SavingsGoalFormView(goal: goal)
            }
            .alert("Delete Goal?", isPresented: deleteBinding) {
                Button("Delete", role: .destructive) {
                    deleteGoal()
                }
                Button("Cancel", role: .cancel) {
                    deletingGoal = nil
                }
            } message: {
                Text("The goal is removed. Its category and transactions stay in your tracker.")
            }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private var deleteBinding: Binding<Bool> {
        Binding {
            deletingGoal != nil
        } set: { isPresented in
            if !isPresented {
                deletingGoal = nil
            }
        }
    }

    private func row(_ goal: SavingsGoal) -> some View {
        SavingsGoalRow(progress: GoalEngine.progress(for: goal), isArchived: goal.isArchived)
            .contentShape(Rectangle())
            .onTapGesture {
                editingGoal = goal
            }
            .contextMenu {
                Button {
                    editingGoal = goal
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    setArchived(goal, !goal.isArchived)
                } label: {
                    Label(goal.isArchived ? "Unarchive" : "Archive", systemImage: goal.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
                Divider()
                Button(role: .destructive) {
                    deletingGoal = goal
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    deletingGoal = goal
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    setArchived(goal, !goal.isArchived)
                } label: {
                    Label(goal.isArchived ? "Unarchive" : "Archive", systemImage: goal.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
                .tint(.gray)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens goal editor")
            .accessibilityAddTraits(.isButton)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = activeGoals
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, goal) in ordered.enumerated() {
            goal.sortOrder = index
        }
        WidgetSnapshotWriter.write(context: modelContext)
    }

    private func setArchived(_ goal: SavingsGoal, _ archived: Bool) {
        goal.isArchived = archived
        if !archived {
            goal.sortOrder = (activeGoals.map(\.sortOrder).max() ?? -1) + 1
        }
        WidgetSnapshotWriter.write(context: modelContext)
    }

    private func deleteGoal() {
        guard let goal = deletingGoal else { return }
        modelContext.delete(goal)
        deletingGoal = nil
        try? modelContext.save()
        WidgetSnapshotWriter.write(context: modelContext)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ContentUnavailableView(
                "No savings goals yet",
                systemImage: "target",
                description: Text("Set a target, link a category and track how close you are.")
            )

            Button("Add Goal") {
                showAdd = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct SavingsGoalRow: View {
    let progress: GoalEngine.Progress
    let isArchived: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GoalIcon(iconName: progress.iconName, colorHex: progress.colorHex, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(progress.name)
                        .fontWeight(.medium)
                    Text(progress.categoryName ?? "No category linked")
                        .font(.caption2)
                        .foregroundStyle(progress.categoryName == nil ? Color.orange : Color.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(progress.amountText)
                        .font(.callout.monospacedDigit())
                    GoalStatusBadge(status: progress.status)
                }
            }

            ProgressView(value: progress.fraction)
                .tint(progress.tint)
                .accessibilityLabel("\(progress.name) progress")
                .accessibilityValue("\(progress.percent) percent")

            if let paceText = progress.paceText {
                Text(paceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(isArchived ? 0.6 : 1)
    }
}
