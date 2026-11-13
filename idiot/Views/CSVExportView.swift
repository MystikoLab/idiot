import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date) private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var startDate = Date.now.startOfMonth
    @State private var endDate = Date.now
    @State private var selectedCategoryIDs: Set<Category.ID> = []
    @State private var didLoad = false
    @State private var exportDocument: CSVDocument?
    @State private var exportError: String?

    private var rangeTransactions: [Transaction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        return transactions.filter { $0.date >= start && $0.date < end }
    }

    private var filteredTransactions: [Transaction] {
        rangeTransactions.filter { transaction in
            guard let id = transaction.category?.id else { return false }
            return selectedCategoryIDs.contains(id)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                categoriesSection
                summarySection
            }
            .formStyle(.grouped)
            .navigationTitle("Export CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    #if os(iOS)
                        ShareLink(
                            item: CSVFile(text: CSVExporter.csv(for: filteredTransactions), filename: filename),
                            preview: SharePreview("\(filename).csv")
                        ) {
                            Label("Share \(filteredTransactions.count)", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(filteredTransactions.isEmpty)
                    #else
                        Button("Export \(filteredTransactions.count)") {
                            exportDocument = CSVDocument(text: CSVExporter.csv(for: filteredTransactions))
                        }
                        .disabled(filteredTransactions.isEmpty)
                    #endif
                }
            }
            .fileExporter(
                isPresented: exportBinding,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: filename
            ) { result in
                switch result {
                case .success:
                    dismiss()
                case let .failure(error):
                    exportError = error.localizedDescription
                }
            }
            .alert("Export Failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "Unknown error.")
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                selectedCategoryIDs = Set(categories.map(\.id))
                applyAllTime()
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
    }

    private var dateSection: some View {
        Section {
            HStack(spacing: 8) {
                presetButton("This Month") {
                    startDate = Date.now.startOfMonth
                    endDate = .now
                }
                presetButton("Last Month") {
                    let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
                    startDate = lastMonth.startOfMonth
                    endDate = lastMonth.endOfMonth
                }
                presetButton("This Year") {
                    startDate = Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now
                    endDate = .now
                }
                presetButton("All Time", action: applyAllTime)
            }
            DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
            DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
        } header: {
            Text("Date Range")
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func applyAllTime() {
        startDate = transactions.first?.date ?? .now
        endDate = max(transactions.last?.date ?? .now, .now)
    }

    private var categoriesSection: some View {
        Section {
            ForEach(CategoryType.allCases.sorted { $0.sortRank < $1.sortRank }) { type in
                let group = categories.filter { $0.type == type }
                if !group.isEmpty {
                    Text(type.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group, content: categoryRow)
                }
            }
        } header: {
            HStack {
                Text("Categories")
                Spacer()
                Button("All") {
                    selectedCategoryIDs = Set(categories.map(\.id))
                }
                Button("None") {
                    selectedCategoryIDs = []
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        let count = rangeTransactions.filter { $0.category?.id == category.id }.count
        let isSelected = selectedCategoryIDs.contains(category.id)
        return Button {
            if isSelected {
                selectedCategoryIDs.remove(category.id)
            } else {
                selectedCategoryIDs.insert(category.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Image(systemName: category.iconName)
                    .foregroundStyle(Color(hex: category.colorHex))
                    .frame(width: 20)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var summarySection: some View {
        let inflow = filteredTransactions.map(\.signedCashAmount).filter { $0 > 0 }.reduce(0, +)
        let outflow = -filteredTransactions.map(\.signedCashAmount).filter { $0 < 0 }.reduce(0, +)
        return Section {
            LabeledContent("Transactions", value: "\(filteredTransactions.count)")
            LabeledContent("Money in") {
                Text("+\(inflow.formattedCurrency)")
                    .foregroundStyle(.green)
            }
            LabeledContent("Money out") {
                Text("−\(outflow.formattedCurrency)")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Columns: Date, Title, Description, Category, Sub Category, Type, Amount. The category filter matches the main category. Income and investment returns are positive, spending and contributions negative.")
        }
        .monospacedDigit()
    }

    private var filename: String {
        let format = Date.ISO8601FormatStyle().year().month().day()
        return "idiot-transactions-\(startDate.formatted(format))-to-\(endDate.formatted(format))"
    }

    private var exportBinding: Binding<Bool> {
        Binding {
            exportDocument != nil
        } set: { isPresented in
            if !isPresented {
                exportDocument = nil
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            exportError != nil
        } set: { isPresented in
            if !isPresented {
                exportError = nil
            }
        }
    }
}
