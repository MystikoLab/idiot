import SwiftData
import SwiftUI

struct RecurringFormView: View {
    enum Mode {
        case subscription
        case salary
    }

    let mode: Mode
    let rule: RecurringRule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var title = ""
    @State private var amount = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var dayNumber = 1
    @State private var selectedCategory: Category?
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var isActive = true
    @State private var showValidation = false

    private var type: CategoryType {
        mode == .salary ? .income : .expense
    }

    private var matchingCategories: [Category] {
        allCategories
            .filter { $0.type == type }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    init(mode: Mode, rule: RecurringRule? = nil) {
        self.mode = mode
        self.rule = rule
        _title = State(initialValue: rule?.title ?? "")
        _amount = State(initialValue: rule.map { String(format: "%.2f", $0.amount) } ?? "")
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _dayNumber = State(initialValue: rule?.dayNumber ?? 1)
        _selectedCategory = State(initialValue: rule?.category)
        _startDate = State(initialValue: rule?.startDate ?? .now)
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? .now)
        _isActive = State(initialValue: rule?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif

                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }

                    if frequency == .monthly {
                        Stepper("Day of month: \(dayNumber)", value: $dayNumber, in: 1 ... 28)
                    }
                }

                Section(type == .income ? "Income Category" : "Expense Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(matchingCategories) { category in
                            Text(category.name).tag(Category?.some(category))
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Ends", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("End date", selection: $endDate, displayedComponents: .date)
                    }
                    Toggle("Active", isOn: $isActive)
                }

                if showValidation {
                    Section {
                        Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Title is required." : "Amount must be greater than 0.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(rule == nil ? (mode == .salary ? "New Salary" : "New Subscription") : "Edit Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
            .frame(minWidth: 440, minHeight: 420)
            #endif
            .onAppear {
                selectedCategory = selectedCategory ?? matchingCategories.first
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAmount = Double(amount) ?? 0
        guard !trimmedTitle.isEmpty, parsedAmount > 0, let selectedCategory else {
            showValidation = true
            return
        }

        let resolvedEndDate = hasEndDate ? endDate : nil

        if let rule {
            rule.title = trimmedTitle
            rule.amount = parsedAmount
            rule.frequency = frequency
            rule.dayNumber = dayNumber
            rule.category = selectedCategory
            rule.startDate = startDate
            rule.endDate = resolvedEndDate
            rule.isActive = isActive
        } else {
            modelContext.insert(RecurringRule(
                title: trimmedTitle,
                amount: parsedAmount,
                frequency: frequency,
                dayNumber: dayNumber,
                category: selectedCategory,
                startDate: startDate,
                endDate: resolvedEndDate,
                isActive: isActive
            ))
        }

        RecurringEngine.materialize(context: modelContext)
        NotificationManager.shared.refresh()
        dismiss()
    }
}
