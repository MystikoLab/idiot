import SwiftData
import SwiftUI

struct CategoryEditView: View {
    private let category: Category?
    private let colorOptions = ["#4F8EF7", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#FFCC00", "#FF2D55", "#5AC8FA"]

    private let iconOptions: [(symbol: String, label: String)] = [
        ("tag.fill", "Tag / General"),
        ("briefcase.fill", "Business"),
        ("bolt.fill", "Utilities"),
        ("fork.knife", "Food & Dining"),
        ("basket.fill", "Groceries"),
        ("car.fill", "Transport"),
        ("desktopcomputer", "Technology"),
        ("person.fill", "Personal"),
        ("dollarsign.circle.fill", "Salary"),
        ("bag.fill", "Shopping"),
        ("house.fill", "Home"),
        ("heart.fill", "Health"),
        ("chart.line.uptrend.xyaxis", "Investments"),
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var name: String
    @State private var type: CategoryType
    @State private var limit: String
    @State private var colorHex: String
    @State private var customColor: Color
    @State private var iconName: String
    @State private var budgetAlertsEnabled: Bool
    @State private var showValidation = false

    init(category: Category? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.type ?? .expense)
        _limit = State(initialValue: category?.limit.map { String(format: "%.2f", $0) } ?? "")
        _colorHex = State(initialValue: category?.colorHex ?? "#4F8EF7")
        _customColor = State(initialValue: Color(hex: category?.colorHex ?? "#4F8EF7"))
        _iconName = State(initialValue: category?.iconName ?? "tag.fill")
        _budgetAlertsEnabled = State(initialValue: category?.budgetAlertsEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $type) {
                        ForEach(CategoryType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    if type == .expense {
                        TextField("Monthly limit (optional)", text: $limit)

                        if hasLimit {
                            Toggle("Budget alerts", isOn: $budgetAlertsEnabled)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 8), spacing: 10) {
                        ForEach(colorOptions, id: \.self) { option in
                            Button {
                                colorHex = option
                                customColor = Color(hex: option)
                            } label: {
                                Circle()
                                    .fill(Color(hex: option))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if colorHex == option {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Custom")
                        Spacer()
                        ColorPicker("Pick a colour", selection: $customColor)
                            .labelsHidden()
                            .fixedSize()
                    }
                    .onChange(of: customColor) {
                        colorHex = customColor.hex
                    }
                }

                Section("Icon") {
                    Picker("Icon", selection: $iconName) {
                        ForEach(iconOptions, id: \.symbol) { option in
                            Label(option.label, systemImage: option.symbol).tag(option.symbol)
                        }
                        if !iconOptions.contains(where: { $0.symbol == iconName }) {
                            Label(iconName, systemImage: iconName).tag(iconName)
                        }
                    }
                }

                if showValidation, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Name is required.")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
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
            .frame(minWidth: 420, minHeight: 420)
            #endif
        }
    }

    private var hasLimit: Bool {
        (Double(limit.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showValidation = true
            return
        }

        let parsedLimit = Double(limit.trimmingCharacters(in: .whitespacesAndNewlines))
        let resolvedLimit = type == .expense ? parsedLimit : nil

        if let category {
            category.name = trimmedName
            category.type = type
            category.limit = resolvedLimit
            category.colorHex = colorHex
            category.iconName = iconName
            category.budgetAlertsEnabled = budgetAlertsEnabled
        } else {
            let nextSortOrder = (categories.filter { $0.type == type }.map(\.sortOrder).max() ?? 0) + 1
            let created = Category(
                name: trimmedName,
                type: type,
                limit: resolvedLimit,
                colorHex: colorHex,
                iconName: iconName,
                sortOrder: nextSortOrder
            )
            created.budgetAlertsEnabled = budgetAlertsEnabled
            modelContext.insert(created)
        }

        NotificationManager.shared.refresh()

        dismiss()
    }
}
