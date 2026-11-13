import SwiftData
import SwiftUI

struct SavingsGoalFormView: View {
    private let goal: SavingsGoal?
    private let colorOptions = ["#34C759", "#4F8EF7", "#FF9500", "#FF3B30", "#AF52DE", "#FFCC00", "#FF2D55", "#5AC8FA"]

    private let iconOptions: [(symbol: String, label: String)] = [
        ("target", "Goal"),
        ("airplane", "Travel"),
        ("house.fill", "Home"),
        ("car.fill", "Car"),
        ("graduationcap.fill", "Education"),
        ("gift.fill", "Gift"),
        ("laptopcomputer", "Technology"),
        ("heart.fill", "Health"),
        ("banknote.fill", "Emergency Fund"),
        ("chart.line.uptrend.xyaxis", "Investments"),
        ("star.fill", "Other"),
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var goals: [SavingsGoal]

    @State private var name: String
    @State private var target: String
    @State private var selectedCategory: Category?
    @State private var startDate: Date
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var colorHex: String
    @State private var customColor: Color
    @State private var iconName: String
    @State private var showValidation = false

    init(goal: SavingsGoal? = nil) {
        self.goal = goal
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal.map { String(format: "%.2f", $0.targetAmount) } ?? "")
        _selectedCategory = State(initialValue: goal?.category)
        _startDate = State(initialValue: goal?.startDate ?? today)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? calendar.date(byAdding: .month, value: 6, to: today) ?? today)
        _colorHex = State(initialValue: goal?.colorHex ?? "#34C759")
        _customColor = State(initialValue: Color(hex: goal?.colorHex ?? "#34C759"))
        _iconName = State(initialValue: goal?.iconName ?? "target")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedTarget: Double {
        Double(target.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var canCreateCategory: Bool {
        !trimmedName.isEmpty && !categories.contains {
            $0.type == .investment && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Target amount", text: $target)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }

                categorySection

                Section("Schedule") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Toggle("Deadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Reach it by", selection: $deadline, displayedComponents: .date)
                    }
                }

                colorSection

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

                if showValidation {
                    Section {
                        Text(trimmedName.isEmpty ? "Name is required." : "Target amount must be greater than 0.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
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
            .frame(minWidth: 440, minHeight: 520)
            #endif
        }
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $selectedCategory) {
                Text("None").tag(Category?.none)
                ForEach(CategoryType.allCases) { type in
                    let matching = categories.filter { $0.type == type }
                    if !matching.isEmpty {
                        Section(type.displayName) {
                            ForEach(matching) { category in
                                Text(category.name).tag(Category?.some(category))
                            }
                        }
                    }
                }
            }

            if canCreateCategory {
                Button {
                    createCategory()
                } label: {
                    Label("Create investment category “\(trimmedName)”", systemImage: "plus")
                }
            }
        } header: {
            Text("Linked Category")
        } footer: {
            Text("Progress is the money logged in this category from the start date onward. Investment categories count contributions minus returns.")
        }
    }

    private var colorSection: some View {
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
    }

    private func createCategory() {
        let nextSortOrder = (categories.filter { $0.type == .investment }.map(\.sortOrder).max() ?? 0) + 1
        let category = Category(
            name: trimmedName,
            type: .investment,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: nextSortOrder
        )
        modelContext.insert(category)
        selectedCategory = category
    }

    private func save() {
        guard !trimmedName.isEmpty, parsedTarget > 0 else {
            showValidation = true
            return
        }

        let calendar = Calendar.current
        let resolvedStart = calendar.startOfDay(for: startDate)
        let resolvedDeadline = hasDeadline ? calendar.startOfDay(for: deadline) : nil

        if let goal {
            goal.name = trimmedName
            goal.targetAmount = parsedTarget
            goal.category = selectedCategory
            goal.startDate = resolvedStart
            goal.deadline = resolvedDeadline
            goal.colorHex = colorHex
            goal.iconName = iconName
        } else {
            let nextSortOrder = (goals.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(SavingsGoal(
                name: trimmedName,
                targetAmount: parsedTarget,
                startDate: resolvedStart,
                deadline: resolvedDeadline,
                iconName: iconName,
                colorHex: colorHex,
                sortOrder: nextSortOrder,
                category: selectedCategory
            ))
        }

        try? modelContext.save()
        WidgetSnapshotWriter.write(context: modelContext)
        dismiss()
    }
}
