import SwiftData
import SwiftUI

struct ImportDraft: Identifiable {
    let id = UUID()
    let original: String
    let sourceCategory: String?
    let isDuplicate: Bool
    let isInflow: Bool
    var assignedCategoryID: UUID?
    var isAutoCategorized = false
    var isIncluded: Bool
    var title: String
    var date: Date
    var amountText: String
    var category: Category?
    var subCategory: Category?
    var isInvestmentReturn: Bool

    var amount: Double {
        Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0 && category != nil
    }

    var hasManualCategory: Bool {
        category?.id != assignedCategoryID
    }

    var signedAmount: Double {
        switch category?.type {
        case .income:
            amount
        case .investment:
            isInvestmentReturn ? amount : -amount
        default:
            -amount
        }
    }
}

struct CSVImportView: View {
    let rows: [CSVImporter.Row]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var drafts: [ImportDraft] = []
    @State private var showValidation = false
    @State private var categorizeTask: Task<Void, Never>?
    @State private var categorizeDone = 0
    @State private var categorizeTotal = 0
    @State private var categorizeSummary: String?

    private let autoCategorizeActive = AutoCategorizer.isActive

    private var included: [ImportDraft] {
        drafts.filter(\.isIncluded)
    }

    private var duplicateCount: Int {
        drafts.filter(\.isDuplicate).count
    }

    var body: some View {
        NavigationStack {
            List {
                if autoCategorizeActive {
                    autoCategorizeSection
                }
                Section {
                    ForEach($drafts) { $draft in
                        CSVImportRow(draft: $draft, categories: categories, showValidation: showValidation)
                    }
                } header: {
                    summaryHeader
                } footer: {
                    Text("Only checked rows are added. Existing transactions are never changed or removed. If you rename a row, the statement's original text is kept as its description.")
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Select All") { setIncluded(true) }
                        Button("Select None") { setIncluded(false) }
                        if duplicateCount > 0 {
                            Button("Deselect Possible Duplicates") {
                                for index in drafts.indices where drafts[index].isDuplicate {
                                    drafts[index].isIncluded = false
                                }
                            }
                        }
                    } label: {
                        Label("Selection", systemImage: "checklist")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(included.count)") {
                        importSelected()
                    }
                    .disabled(included.isEmpty)
                }
            }
            .onAppear {
                if drafts.isEmpty {
                    drafts = makeDrafts()
                }
            }
            .onDisappear {
                categorizeTask?.cancel()
            }
            #if os(macOS)
            .frame(minWidth: 680, minHeight: 480)
            #endif
        }
    }

    private var summaryHeader: some View {
        let income = included.filter { $0.signedAmount > 0 }.reduce(0) { $0 + $1.amount }
        let outflow = included.filter { $0.signedAmount < 0 }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(included.count) of \(drafts.count) selected")
                Spacer()
                Text("+\(income.formattedCurrency)")
                    .foregroundStyle(.green)
                Text("−\(outflow.formattedCurrency)")
                    .foregroundStyle(.red)
            }
            .monospacedDigit()
            if duplicateCount > 0 {
                Label("\(duplicateCount) possible duplicate\(duplicateCount == 1 ? "" : "s") unchecked", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .textCase(nil)
    }

    private var autoCategorizeSection: some View {
        Section {
            if categorizeTask != nil {
                HStack(spacing: 10) {
                    ProgressView(value: Double(categorizeDone), total: Double(max(categorizeTotal, 1)))
                    Text("\(categorizeDone) of \(categorizeTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Cancel") {
                        categorizeTask?.cancel()
                    }
                }
            } else {
                Button {
                    startCategorizing()
                } label: {
                    Label("Categorize with Apple Intelligence", systemImage: "sparkles")
                }
                .disabled(drafts.isEmpty)
            }
        } footer: {
            Text(categorizeSummary ?? "Fills in categories from your history, then on-device Apple Intelligence for new names. Rows whose category you changed are left alone, and you can still edit every row.")
        }
    }

    private func startCategorizing() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let history = AutoCategorizer.History(existing)
        let requests = drafts.filter { !$0.hasManualCategory }.map { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = [title == draft.original ? nil : draft.original, draft.sourceCategory]
                .compactMap { $0 }
                .joined(separator: " · ")
            return (id: draft.id, request: AutoCategorizer.Request(
                title: title.isEmpty ? draft.original : title,
                details: details.isEmpty ? nil : details,
                amount: draft.amount > 0 ? draft.amount : nil,
                candidates: categories.filter { $0.type == .investment || ($0.type == .income) == draft.isInflow }
            ))
        }
        categorizeDone = 0
        categorizeTotal = requests.count
        categorizeSummary = nil

        categorizeTask = Task {
            var filled = 0
            await AutoCategorizer.resolve(requests, history: history) { done in
                categorizeDone = done
            } onResult: { id, category in
                guard let index = drafts.firstIndex(where: { $0.id == id }), !drafts[index].hasManualCategory else { return }
                drafts[index].category = category
                drafts[index].assignedCategoryID = category.id
                drafts[index].isAutoCategorized = true
                drafts[index].isInvestmentReturn = category.type == .investment && drafts[index].isInflow
                filled += 1
            }
            let stopped = Task.isCancelled ? "Stopped. " : ""
            categorizeSummary = "\(stopped)Categorized \(filled) of \(requests.count) row\(requests.count == 1 ? "" : "s"). Rows without a confident match were left unchanged."
            categorizeTask = nil
        }
    }

    private func setIncluded(_ value: Bool) {
        for index in drafts.indices {
            drafts[index].isIncluded = value
        }
    }

    private func makeDrafts() -> [ImportDraft] {
        let existing = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let calendar = Calendar.current
        let existingKeys = Set(existing.map { duplicateKey(date: $0.date, amount: $0.amount, calendar: calendar) })
        var history: [String: Category] = [:]
        for transaction in existing {
            if let category = transaction.category {
                history[transaction.title.lowercased()] = category
            }
        }

        return rows.map { row in
            let isDuplicate = existingKeys.contains(duplicateKey(date: row.date, amount: abs(row.amount), calendar: calendar))
            let category = suggestedCategory(for: row, history: history)
            let subName = row.sourceSubCategory?.lowercased()
            return ImportDraft(
                original: row.description,
                sourceCategory: row.sourceCategory,
                isDuplicate: isDuplicate,
                isInflow: row.amount > 0,
                assignedCategoryID: category?.id,
                isIncluded: !isDuplicate,
                title: row.description,
                date: row.date,
                amountText: String(format: "%.2f", abs(row.amount)),
                category: category,
                subCategory: subName.flatMap { name in categories.first { $0.name.lowercased() == name } },
                isInvestmentReturn: category?.type == .investment && row.amount > 0
            )
        }
    }

    private func duplicateKey(date: Date, amount: Double, calendar: Calendar) -> String {
        "\(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)|\(Int((amount * 100).rounded()))"
    }

    private func suggestedCategory(for row: CSVImporter.Row, history: [String: Category]) -> Category? {
        let isInflow = row.amount > 0
        let compatible: (Category) -> Bool = { category in
            category.type == .investment || (category.type == .income) == isInflow
        }

        if let previous = history[row.description.lowercased()], compatible(previous) {
            return previous
        }
        if let source = row.sourceCategory?.lowercased(),
           let match = categories.first(where: { $0.name.lowercased() == source && compatible($0) })
        {
            return match
        }
        let type: CategoryType = isInflow ? .income : .expense
        return categories.first { $0.type == type }
    }

    private func importSelected() {
        guard included.allSatisfy(\.isValid) else {
            showValidation = true
            return
        }

        for draft in included {
            guard let category = draft.category else { continue }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            modelContext.insert(Transaction(
                title: title,
                desc: title == draft.original ? nil : draft.original,
                amount: draft.amount,
                date: draft.date,
                category: category,
                subCategory: draft.subCategory?.id == category.id ? nil : draft.subCategory,
                isInvestmentReturn: category.type == .investment && draft.isInvestmentReturn
            ))
        }
        try? modelContext.save()
        WidgetSnapshotWriter.write(context: modelContext)
        dismiss()
    }
}

private struct CSVImportRow: View {
    @Binding var draft: ImportDraft
    let categories: [Category]
    let showValidation: Bool

    private var amountColor: Color {
        if draft.category?.type == .investment {
            return .investment
        }
        return draft.signedAmount > 0 ? .green : .red
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                draft.isIncluded.toggle()
            } label: {
                Image(systemName: draft.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(draft.isIncluded ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.isIncluded ? "Included" : "Excluded")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                    Text(draft.signedAmount > 0 ? "+" : "−")
                        .fontWeight(.semibold)
                        .foregroundStyle(amountColor)
                    TextField("Amount", text: $draft.amountText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 100)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }

                HStack(spacing: 8) {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .labelsHidden()
                    categoryPicker
                    if draft.category?.type == .investment {
                        Picker("Direction", selection: $draft.isInvestmentReturn) {
                            Text("Contribution").tag(false)
                            Text("Return").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                detailLine
            }
        }
        .padding(.vertical, 4)
        .opacity(draft.isIncluded ? 1 : 0.5)
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $draft.category) {
            Text("Select a category").tag(Category?.none)
            ForEach(categories) { category in
                Label {
                    Text("\(category.type.displayName): \(category.name)")
                } icon: {
                    Image(systemName: category.iconName)
                        .foregroundStyle(Color(hex: category.colorHex))
                }
                .tag(Category?.some(category))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var detailLine: some View {
        let errors = validationErrors
        HStack(spacing: 6) {
            if draft.isAutoCategorized, !draft.hasManualCategory {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .accessibilityLabel("Categorized automatically")
            }
            if draft.isDuplicate {
                Label("Possible duplicate", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if draft.title != draft.original {
                Text("Statement: \(draft.original)")
                    .lineLimit(1)
            }
            if let source = draft.sourceCategory {
                Text("· \(source)")
            }
            if let sub = draft.subCategory, sub.id != draft.category?.id {
                Text("· Sub: \(sub.name)")
            }
            if !errors.isEmpty {
                Text(errors.joined(separator: " "))
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var validationErrors: [String] {
        guard showValidation, draft.isIncluded else { return [] }
        var errors: [String] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title is required.")
        }
        if draft.amount <= 0 {
            errors.append("Amount must be greater than 0.")
        }
        if draft.category == nil {
            errors.append("Choose a category.")
        }
        return errors
    }
}
