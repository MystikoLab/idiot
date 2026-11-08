import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var transactions: [Transaction]

    @AppStorage("lockPastMonths") private var lockPastMonths = true
    @State private var showAddCategory = false
    @State private var startingAmountText: String = ""
    @State private var editingCategory: Category?
    @State private var pendingDeleteCategory: Category?
    @State private var isPushing = false
    @State private var pushError: String?
    @State private var showEraseConfirmation = false
    private let syncMonitor = CloudSyncMonitor.shared

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var incomeCategories: [Category] {
        categories.filter { $0.type == .income }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var investmentCategories: [Category] {
        categories.filter { $0.type == .investment }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                categoriesSection
                recurringSection
                helpSection
                lockSection
                startingAmountSection
                advancedSection
                #if os(macOS)
                    MCPSettingsSection()
                #endif
                dangerSection
            }
            .navigationTitle("Settings")
            .task {
                await syncMonitor.refreshAccountStatus()
            }
            .onAppear {
                if startingAmountText.isEmpty {
                    let amount = OpeningBalance.amount
                    startingAmountText = amount == 0 ? "" : String(format: "%.2f", amount)
                }
            }
            .onChange(of: startingAmountText) {
                OpeningBalance.set(Double(startingAmountText.trimmingCharacters(in: .whitespaces)) ?? 0)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddCategory) {
                CategoryEditView()
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditView(category: category)
            }
            .alert("Delete Category?", isPresented: deleteConfirmationBinding) {
                Button("Delete", role: .destructive) {
                    if let pendingDeleteCategory {
                        deleteCategory(pendingDeleteCategory)
                    }
                    pendingDeleteCategory = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteCategory = nil
                }
            } message: {
                Text(deleteMessage)
            }
            .alert("Erase All Data?", isPresented: $showEraseConfirmation) {
                Button("Erase Everything", role: .destructive) {
                    eraseAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All transactions, categories, and recurring rules will be removed from this device and iCloud. This cannot be undone.")
            }
            .alert("Force Push Failed", isPresented: pushErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pushError ?? "Unknown error.")
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
            #endif
        }
    }

    private func eraseAllData() {
        do {
            for transaction in try modelContext.fetch(FetchDescriptor<Transaction>()) {
                modelContext.delete(transaction)
            }
            for rule in try modelContext.fetch(FetchDescriptor<RecurringRule>()) {
                modelContext.delete(rule)
            }
            for category in try modelContext.fetch(FetchDescriptor<Category>()) {
                modelContext.delete(category)
            }
            try modelContext.save()
            DefaultCategories.seed(context: modelContext)
            WidgetSnapshotWriter.write(context: modelContext)
        } catch {
            assertionFailure("Failed to erase data: \(error.localizedDescription)")
        }
    }

    private func forcePush() {
        guard !isPushing else { return }
        isPushing = true
        pushError = nil

        Task {
            do {
                let now = Date()
                for transaction in try modelContext.fetch(FetchDescriptor<Transaction>()) {
                    transaction.syncStamp = now
                }
                for category in try modelContext.fetch(FetchDescriptor<Category>()) {
                    category.syncStamp = now
                }
                try modelContext.save()
            } catch {
                pushError = error.localizedDescription
            }
            isPushing = false
        }
    }

    private var pushErrorBinding: Binding<Bool> {
        Binding {
            pushError != nil
        } set: { isPresented in
            if !isPresented {
                pushError = nil
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            pendingDeleteCategory != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeleteCategory = nil
            }
        }
    }

    @ViewBuilder
    private var categoryListRows: some View {
        if categories.isEmpty {
            Text("No categories yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(expenseCategories, content: categoryListRow)
                .accessibilityElement(children: .contain)
            ForEach(incomeCategories, content: categoryListRow)
            ForEach(investmentCategories, content: categoryListRow)
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            categoryListRows

            Button {
                showAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus")
            }
        }
    }

    private var recurringSection: some View {
        Section {
            NavigationLink(destination: RecurringListView()) {
                Label("Subscriptions & Auto Salary", systemImage: "repeat")
            }
            .accessibilityLabel("Manage Recurring Rules")
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink(destination: helpDestination) {
                Label("Help & Savings Guide", systemImage: "questionmark.circle")
            }
        }
    }

    private var lockSection: some View {
        Section {
            Toggle("Lock past months from editing", isOn: $lockPastMonths)
        } footer: {
            Text("When enabled, transactions in previous months cannot be edited, copied, or deleted.")
        }
    }

    private var startingAmountSection: some View {
        Section {
            TextField("Starting amount", text: $startingAmountText)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
        } header: {
            Text("Starting Amount")
        } footer: {
            Text("Added to your balance everywhere in the app without creating a transaction or counting as income.")
        }
    }

    private var advancedSection: some View {
        Section {
            let statusColor: Color = syncMonitor.showsError ? Color.red : Color.secondary
            LabeledContent("iCloud Status") {
                Text(syncMonitor.statusText)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
            }

            Button {
                forcePush()
            } label: {
                HStack {
                    Label("Force Push to iCloud", systemImage: "icloud.and.arrow.up")
                    if isPushing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPushing)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Changes sync automatically. Use Force Push if a device seems out of date — it re-uploads all local data to your private iCloud database.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showEraseConfirmation = true
            } label: {
                Label("Erase All Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Deletes every transaction, category, and recurring rule — locally and from iCloud. This cannot be undone.")
        }
    }

    private var helpDestination: some View {
        HelpView()
    }

    private func categoryListRow(_ category: Category) -> some View {
        #if os(iOS)
            return SettingsCategoryRow(category: category, spent: currentMonthSpent(for: category), onEdit: onEditCategory, onDelete: requestDelete)
                .swipeActions {
                    Button(role: .destructive) { requestDelete(category) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        #else
            return SettingsCategoryRow(category: category, spent: currentMonthSpent(for: category), onEdit: onEditCategory, onDelete: requestDelete)
        #endif
    }

    private func onEditCategory(_ category: Category) {
        editingCategory = category
    }

    private func currentMonthSpent(for category: Category) -> Double {
        let start = Date.now.startOfMonth
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? Date.now.endOfMonth

        return transactions
            .filter { transaction in
                transaction.category?.id == category.id &&
                    transaction.date >= start &&
                    transaction.date < end
            }
            .reduce(0) { $0 + $1.amount }
    }

    private var deleteMessage: String {
        guard let category = pendingDeleteCategory else {
            return "This will remove the category from your tracker."
        }

        let count = category.transactions?.count ?? 0
        guard count > 0 else {
            return "This will remove the category from your tracker."
        }

        return "This will remove the category and its \(count) transaction\(count == 1 ? "" : "s") from your tracker."
    }

    private func deleteCategory(_ category: Category) {
        for transaction in category.transactions ?? [] {
            modelContext.delete(transaction)
        }
        modelContext.delete(category)

        try? modelContext.save()
        WidgetSnapshotWriter.write(context: modelContext)
    }

    private func requestDelete(_ category: Category) {
        pendingDeleteCategory = category
    }
}

struct SettingsCategoryRow: View {
    let category: Category
    let spent: Double
    let onEdit: (Category) -> Void
    let onDelete: (Category) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: category.colorHex))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: category.colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .fontWeight(.medium)
                    Text(category.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if category.type == .expense, let limit = category.limit {
                    Text(limit.formattedCurrency)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if category.type == .investment {
                    investmentSummary
                }
            }

            if category.type == .expense, let limit = category.limit {
                let progress = limit > 0 ? min(spent / limit, 1) : 0

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(spent >= limit ? Color.red : Color(hex: category.colorHex))
                        .accessibilityLabel("\(category.name) budget")
                        .accessibilityValue("\(spent.formattedCurrency) of \(limit.formattedCurrency)")

                    Text("\(spent.formattedCurrency) / \(limit.formattedCurrency) (\(Int((limit > 0 ? spent / limit : 0) * 100))%)")
                        .font(.caption)
                        .foregroundStyle(spent >= limit ? Color.red : Color.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit(category)
        }
        .contextMenu {
            Button {
                onEdit(category)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(category)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens category editor")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onEdit(category)
        }
    }

    private var investmentSummary: some View {
        let transactions = category.transactions ?? []
        let count = transactions.count
        return VStack(alignment: .trailing, spacing: 1) {
            Text(transactions.netInvested.formattedCurrency)
                .foregroundStyle(Color.investment)
                .monospacedDigit()
            Text("\(count) transaction\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
