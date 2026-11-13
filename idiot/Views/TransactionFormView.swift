import SwiftData
import SwiftUI

private struct TransactionDraft: Codable {
    let title: String
    let desc: String
    let amount: String
    let date: Date
    let categoryID: UUID?
    var isInvestmentReturn: Bool?
    var categoryPicked: Bool?
    var subCategoryID: UUID?
}

struct TransactionFormView: View {
    private let transaction: Transaction?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @AppStorage("transactionDraft") private var draftData = ""

    @State private var date: Date
    @State private var title = ""
    @State private var desc = ""
    @State private var amount = ""
    @State private var selectedCategory: Category?
    @State private var subCategory: Category?
    @State private var isInvestmentReturn: Bool
    @State private var showValidation = false
    @State private var showDatePicker = false
    @State private var titleGroups: [TransactionMatcher.TitleGroup] = []
    @State private var pickedTitle: String?
    @State private var categoryHistory = AutoCategorizer.History([])
    @State private var categoryPicked = false
    @State private var categoryIsAuto = false
    @State private var receipts: [ReceiptFile]
    @State private var removedReceiptIDs: Set<UUID> = []
    @State private var receiptSuggestions: [ReceiptSuggestion] = []
    @State private var activeScans = 0
    @FocusState private var titleFocused: Bool

    init(transaction: Transaction? = nil, defaultDate: Date = .now) {
        self.transaction = transaction
        _date = State(initialValue: transaction?.date ?? defaultDate)
        _title = State(initialValue: transaction?.title ?? "")
        _desc = State(initialValue: transaction?.desc ?? "")
        _amount = State(initialValue: transaction.map { String(format: "%.2f", $0.amount) } ?? "")
        _selectedCategory = State(initialValue: transaction?.category)
        _subCategory = State(initialValue: transaction?.subCategory)
        _isInvestmentReturn = State(initialValue: transaction?.isInvestmentReturn ?? false)
        _receipts = State(initialValue: transaction?.sortedAttachments.compactMap(\.file) ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    HStack {
                        Text("Date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showDatePicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .padding()
                                .frame(width: 280)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                            .submitLabel(.next)
                            .overlay {
                                if showValidation, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.red, lineWidth: 1)
                                }
                            }

                        if showValidation, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Title is required.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !suggestions.isEmpty {
                            TransactionSuggestionList(suggestions: suggestions, onPick: applySuggestion)
                        }
                    }

                    TextField("Description (optional)", text: $desc)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Amount", text: $amount)
                            .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                            .submitLabel(.done)

                        if showValidation, (Double(amount) ?? 0) <= 0 {
                            Text("Amount must be greater than 0.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Category") {
                    if categories.isEmpty {
                        ContentUnavailableView("No categories", systemImage: "tag", description: Text("Add a category in Settings first."))
                    } else {
                        Picker("Category", selection: categorySelection) {
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
                        .foregroundStyle(.primary)

                        Picker("Sub category", selection: $subCategory) {
                            Text("None").tag(Category?.none)
                            ForEach(categories.filter { $0.id != selectedCategory?.id }) { category in
                                Label {
                                    Text("\(category.type.displayName): \(category.name)")
                                } icon: {
                                    Image(systemName: category.iconName)
                                        .foregroundStyle(Color(hex: category.colorHex))
                                }
                                .tag(Category?.some(category))
                            }
                        }
                        .foregroundStyle(.primary)
                    }

                    if categoryIsAuto {
                        Label("Picked automatically — change it if it's wrong.", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }

                    if showValidation, selectedCategory == nil {
                        Text("Choose a category.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if selectedCategory?.type == .investment {
                    investmentFlowSection
                }

                ReceiptsSection(
                    files: receipts,
                    suggestions: receiptSuggestions,
                    isScanning: activeScans > 0,
                    onAdd: addReceipts,
                    onRemove: removeReceipt,
                    onApply: applyReceiptSuggestion,
                    onDismiss: dismissReceiptSuggestion
                )
            }
            .formStyle(.grouped)
            .receiptImportTarget(onAdd: addReceipts)
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearDraft()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 360)
            #endif
            .onAppear {
                if transaction == nil {
                    restoreDraft()
                    pickedTitle = title
                    loadTitleGroups()
                    titleFocused = true
                }
                selectedCategory = selectedCategory ?? categories.first
            }
            .task(id: title) {
                await suggestCategory()
            }
            .onChange(of: title) { saveDraft() }
            .onChange(of: desc) { saveDraft() }
            .onChange(of: amount) { saveDraft() }
            .onChange(of: date) { saveDraft() }
            .onChange(of: selectedCategory?.id) {
                if subCategory?.id == selectedCategory?.id {
                    subCategory = nil
                }
                saveDraft()
            }
            .onChange(of: subCategory?.id) { saveDraft() }
            .onChange(of: isInvestmentReturn) { saveDraft() }
        }
    }

    private var investmentFlowSection: some View {
        Section {
            Picker("Direction", selection: $isInvestmentReturn) {
                Text("Contribution").tag(false)
                Text("Return").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Investment")
        } footer: {
            Text(isInvestmentReturn
                ? "Money coming back from this investment, such as a sale or a dividend."
                : "Money you put into this investment.")
        }
    }

    private var suggestions: [TransactionMatcher.TitleGroup] {
        guard transaction == nil, title != pickedTitle else { return [] }
        return TransactionMatcher.suggestions(for: title, in: titleGroups)
    }

    private var categorySelection: Binding<Category?> {
        Binding {
            selectedCategory
        } set: { category in
            selectedCategory = category
            categoryPicked = true
            categoryIsAuto = false
        }
    }

    private func loadTitleGroups() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let past = (try? modelContext.fetch(descriptor)) ?? []
        titleGroups = TransactionMatcher.titleGroups(past)
        categoryHistory = AutoCategorizer.History(past)
    }

    private func suggestCategory() async {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transaction == nil, !categoryPicked, typed.count >= 3, AutoCategorizer.isActive else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }

        let trimmedDesc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = AutoCategorizer.Request(
            title: typed,
            details: trimmedDesc.isEmpty ? nil : trimmedDesc,
            amount: Double(amount).flatMap { $0 > 0 ? $0 : nil },
            candidates: categories
        )
        let suggestion = await AutoCategorizer.suggestion(for: request, history: categoryHistory)
        guard !Task.isCancelled, !categoryPicked, let suggestion else { return }
        selectedCategory = suggestion
        categoryIsAuto = true
    }

    private func applySuggestion(_ source: Transaction) {
        title = source.title
        desc = source.desc ?? ""
        amount = String(format: "%.2f", source.amount)
        if let category = source.category {
            selectedCategory = category
        }
        subCategory = source.subCategory?.id == selectedCategory?.id ? nil : source.subCategory
        isInvestmentReturn = source.isInvestmentReturn
        pickedTitle = source.title
        categoryPicked = true
        categoryIsAuto = false
    }

    private func addReceipts(_ files: [ReceiptFile]) {
        for file in files {
            receipts.append(file)
            Task {
                activeScans += 1
                let result = await ReceiptScanner.scan(file)
                activeScans -= 1
                if receipts.contains(file) {
                    applyScan(result)
                }
            }
        }
    }

    private func removeReceipt(_ file: ReceiptFile) {
        receipts.removeAll { $0.id == file.id }
        removedReceiptIDs.insert(file.id)
    }

    private func applyScan(_ result: ReceiptScanner.Result) {
        if let scanned = result.amount, scanned > 0 {
            if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                amount = String(format: "%.2f", scanned)
            } else if abs((Double(amount) ?? 0) - scanned) >= 0.005 {
                suggest(.amount(scanned))
            }
        }
        if let scanned = result.title {
            let current = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                title = scanned
            } else if current.caseInsensitiveCompare(scanned) != .orderedSame {
                suggest(.title(scanned))
            }
        }
        if let scanned = result.date, !Calendar.current.isDate(scanned, inSameDayAs: date) {
            suggest(.date(scanned))
        }
    }

    private func suggest(_ suggestion: ReceiptSuggestion) {
        receiptSuggestions.removeAll { $0.id == suggestion.id }
        receiptSuggestions.append(suggestion)
    }

    private func applyReceiptSuggestion(_ suggestion: ReceiptSuggestion) {
        switch suggestion {
        case let .amount(value):
            amount = String(format: "%.2f", value)
        case let .title(value):
            title = value
        case let .date(value):
            date = value
        }
        dismissReceiptSuggestion(suggestion)
    }

    private func dismissReceiptSuggestion(_ suggestion: ReceiptSuggestion) {
        receiptSuggestions.removeAll { $0.id == suggestion.id }
    }

    private func saveReceipts(to transaction: Transaction) {
        let existing = transaction.attachments ?? []
        for attachment in existing where removedReceiptIDs.contains(attachment.id) {
            modelContext.delete(attachment)
        }
        let existingIDs = Set(existing.map(\.id))
        for file in receipts where !existingIDs.contains(file.id) {
            let attachment = Attachment(id: file.id, filename: file.filename, contentType: file.contentType, data: file.data)
            modelContext.insert(attachment)
            attachment.transaction = transaction
        }
    }

    private func restoreDraft() {
        guard let draft = try? JSONDecoder().decode(TransactionDraft.self, from: Data(draftData.utf8)) else { return }
        title = draft.title
        desc = draft.desc
        amount = draft.amount
        date = draft.date
        selectedCategory = categories.first { $0.id == draft.categoryID }
        subCategory = categories.first { $0.id == draft.subCategoryID && $0.id != draft.categoryID }
        isInvestmentReturn = draft.isInvestmentReturn ?? false
        categoryPicked = draft.categoryPicked ?? false
    }

    private func saveDraft() {
        guard transaction == nil else { return }
        guard !title.isEmpty || !desc.isEmpty || !amount.isEmpty else {
            draftData = ""
            return
        }
        let draft = TransactionDraft(
            title: title,
            desc: desc,
            amount: amount,
            date: date,
            categoryID: selectedCategory?.id,
            isInvestmentReturn: isInvestmentReturn,
            categoryPicked: categoryPicked,
            subCategoryID: subCategory?.id
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        draftData = String(decoding: data, as: UTF8.self)
    }

    private func clearDraft() {
        if transaction == nil {
            draftData = ""
        }
    }

    private var isEditing: Bool {
        transaction != nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (Double(amount) ?? 0) > 0 &&
            selectedCategory != nil
    }

    private func save() {
        guard canSave, let selectedCategory else {
            showValidation = true
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAmount = Double(amount) ?? 0
        let resolvedReturn = selectedCategory.type == .investment && isInvestmentReturn
        let resolvedSub = subCategory?.id == selectedCategory.id ? nil : subCategory

        if let transaction {
            transaction.title = trimmedTitle
            transaction.desc = trimmedDesc.isEmpty ? nil : trimmedDesc
            transaction.amount = parsedAmount
            transaction.date = date
            transaction.category = selectedCategory
            transaction.subCategory = resolvedSub
            transaction.isInvestmentReturn = resolvedReturn
            saveReceipts(to: transaction)
        } else {
            let created = Transaction(
                title: trimmedTitle,
                desc: trimmedDesc.isEmpty ? nil : trimmedDesc,
                amount: parsedAmount,
                date: date,
                category: selectedCategory,
                subCategory: resolvedSub,
                isInvestmentReturn: resolvedReturn
            )
            modelContext.insert(created)
            saveReceipts(to: created)
        }

        clearDraft()
        dismiss()
    }
}
