import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    enum AnalyticsTab: String, CaseIterable, Identifiable {
        case transactions
        case categories
        case balance
        case forecast
        case comparison
        case patterns

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .transactions: "Transactions"
            case .categories: "Categories"
            case .balance: "Balance & Heatmap"
            case .forecast: "Forecast & Budgets"
            case .comparison: "Comparison & Recurring"
            case .patterns: "Spend Patterns"
            }
        }

        var icon: String {
            switch self {
            case .transactions: "list.bullet.rectangle"
            case .categories: "tag.circle"
            case .balance: "chart.line.uptrend.xyaxis"
            case .forecast: "wand.and.stars"
            case .comparison: "arrow.left.arrow.right.square"
            case .patterns: "clock.badge.questionmark"
            }
        }
    }

    private struct AnalyticsPoint: Identifiable {
        let id = UUID()
        let bucket: Date
        let categoryName: String
        let colorHex: String
        let type: CategoryType
        let amount: Double
    }

    private struct CategoryStat: Identifiable {
        let id: String
        let name: String
        let colorHex: String
        let iconName: String
        let type: CategoryType
        let total: Double
        let transactionCount: Int
        let avgPerTransaction: Double
        let avgPerPeriod: Double
        let percent: Double
    }

    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var recurringRules: [RecurringRule]

    @AppStorage("analyticsFromDate") private var fromDateValue: Double = 0
    @AppStorage("analyticsToDate") private var toDateValue: Double = 0
    @AppStorage("analyticsGranularity") private var granularityRaw = Granularity.monthly.rawValue
    @AppStorage("analyticsShowIncome") private var showIncome = true
    @AppStorage("analyticsShowExpense") private var showExpense = true
    @AppStorage("analyticsMinAmount") private var minAmountText = ""
    @AppStorage("analyticsMaxAmount") private var maxAmountText = ""
    @AppStorage("analyticsSelectedCategoryIDs") private var selectedCategoryIDsData = ""
    @State private var sortAscending = false
    @State private var activeTab: AnalyticsTab = .transactions
    @State private var showFilters = false
    @State private var selectedBucket: Date?
    @State private var chartSize: CGSize = .zero

    private var defaultFromDate: Date {
        (Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now).startOfMonth
    }

    private var fromDate: Date {
        get { fromDateValue == 0 ? defaultFromDate : Date(timeIntervalSinceReferenceDate: fromDateValue) }
        nonmutating set { fromDateValue = newValue.timeIntervalSinceReferenceDate }
    }

    private var toDate: Date {
        get { toDateValue == 0 ? .now : Date(timeIntervalSinceReferenceDate: toDateValue) }
        nonmutating set { toDateValue = newValue.timeIntervalSinceReferenceDate }
    }

    private var fromDateBinding: Binding<Date> {
        Binding { fromDate } set: { fromDate = $0 }
    }

    private var toDateBinding: Binding<Date> {
        Binding { toDate } set: { toDate = $0 }
    }

    private var granularity: Granularity {
        get { Granularity(rawValue: granularityRaw) ?? .monthly }
        nonmutating set { granularityRaw = newValue.rawValue }
    }

    private var granularityBinding: Binding<Granularity> {
        Binding { granularity } set: { granularity = $0 }
    }

    private var selectedCategoryIDs: Set<Category.ID> {
        get {
            Set(selectedCategoryIDsData.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        }
        nonmutating set {
            selectedCategoryIDsData = newValue.map(\.uuidString).sorted().joined(separator: ",")
        }
    }

    private var minAmount: Double? {
        let trimmed = minAmountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var maxAmount: Double? {
        let trimmed = maxAmountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var hasActiveFilters: Bool {
        !showIncome || !showExpense || !minAmountText.isEmpty || !maxAmountText.isEmpty || !selectedCategoryIDs.isEmpty
    }

    private var insightCards: [AnalyticsEngine.Insight] {
        AnalyticsEngine.generateInsights(
            current: filteredTransactions,
            previous: previousTransactions,
            categories: categories,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            granularity: granularity
        )
    }

    private var balancePoints: [AnalyticsEngine.BalancePoint] {
        AnalyticsEngine.cumulativeBalanceSeries(
            allTx: allTransactions,
            rangeTx: filteredTransactions,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
    }

    private var dailyHeatmapTotals: [AnalyticsEngine.DailyAmount] {
        AnalyticsEngine.dailyExpenseTotals(filteredTransactions)
    }

    private var currentMonthForecast: AnalyticsEngine.ForecastResult? {
        let monthStart = Date.now.startOfMonth
        let txs = allTransactions.filter { $0.date >= monthStart && $0.date <= monthStart.endOfMonth }
        return AnalyticsEngine.forecast(month: monthStart, monthTxs: txs, allTx: allTransactions, rules: recurringRules)
    }

    private var recurringSplit: (committed: Double, discretionary: Double) {
        AnalyticsEngine.recurringExpenseShare(filteredTransactions)
    }

    private var ruleSpend: [AnalyticsEngine.RuleSpend] {
        AnalyticsEngine.recurringRuleSpend(filteredTransactions, rules: recurringRules)
    }

    private var weekdaySpend: [AnalyticsEngine.WeekdaySpend] {
        AnalyticsEngine.spendByWeekday(filteredTransactions)
    }

    private var histogram: [AnalyticsEngine.HistogramBucket] {
        AnalyticsEngine.expenseHistogram(filteredTransactions)
    }

    private var rangeStart: Date {
        min(fromDate, toDate).startOfDay
    }

    private var rangeEnd: Date {
        max(fromDate, toDate).endOfDay
    }

    private var previousRange: PeriodRange {
        let span = rangeEnd.timeIntervalSince(rangeStart)
        let start = rangeStart.addingTimeInterval(-span)
        return PeriodRange(start: start, end: max(rangeStart.addingTimeInterval(-1), start))
    }

    private struct PeriodRange {
        let start: Date
        let end: Date
    }

    private func transactions(in range: PeriodRange) -> [Transaction] {
        allTransactions.filter { tx in
            guard tx.date >= range.start, tx.date <= range.end else { return false }
            let type = tx.category?.type ?? .expense
            if type == .income, !showIncome {
                return false
            }
            if type == .expense, !showExpense {
                return false
            }
            if let minVal = minAmount, tx.amount < minVal {
                return false
            }
            if let maxVal = maxAmount, tx.amount > maxVal {
                return false
            }
            if !selectedCategoryIDs.isEmpty {
                guard let category = tx.category, selectedCategoryIDs.contains(category.id) else {
                    return false
                }
            }
            return true
        }
    }

    private var filteredTransactions: [Transaction] {
        transactions(in: PeriodRange(start: rangeStart, end: rangeEnd))
    }

    private var previousTransactions: [Transaction] {
        transactions(in: previousRange)
    }

    private var prevIncomeTotal: Double {
        previousTransactions.filter { ($0.category?.type ?? .expense) == .income }.reduce(0) { $0 + $1.amount }
    }

    private var prevExpenseTotal: Double {
        previousTransactions.filter { ($0.category?.type ?? .expense) == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var prevNetTotal: Double {
        prevIncomeTotal - prevExpenseTotal
    }

    private static func percentDelta(current: Double, previous: Double) -> Double? {
        guard previous != 0 else { return nil }
        return (current - previous) / abs(previous) * 100
    }

    private var sortedTransactions: [Transaction] {
        filteredTransactions.sorted { lhs, rhs in
            if lhs.amount != rhs.amount {
                return sortAscending ? lhs.amount < rhs.amount : lhs.amount > rhs.amount
            }
            return sortAscending ? lhs.date < rhs.date : lhs.date > rhs.date
        }
    }

    private var chartData: [AnalyticsPoint] {
        Dictionary(grouping: filteredTransactions) { tx in
            BucketKey(bucket: tx.date.start(of: granularity), name: tx.category?.name ?? "Uncategorized")
        }
        .compactMap { _, txs -> AnalyticsPoint? in
            guard let first = txs.first else { return nil }
            let type = first.category?.type ?? .expense
            let total = txs.reduce(0) { $0 + $1.amount }
            return AnalyticsPoint(
                bucket: first.date.start(of: granularity),
                categoryName: first.category?.name ?? "Uncategorized",
                colorHex: first.category?.colorHex ?? "#8E8E93",
                type: type,
                amount: type == .expense ? -total : total
            )
        }
        .sorted {
            if $0.bucket != $1.bucket {
                return $0.bucket < $1.bucket
            }
            return $0.amount > $1.amount
        }
    }

    private var colorDomain: [String] {
        Array(Set(chartData.map(\.categoryName))).sorted()
    }

    private var colorRange: [Color] {
        colorDomain.map { name in
            let hex = chartData.first { $0.categoryName == name }?.colorHex ?? "#8E8E93"
            return Color(hex: hex)
        }
    }

    private var incomeTotal: Double {
        filteredTransactions.filter { ($0.category?.type ?? .expense) == .income }.reduce(0) { $0 + $1.amount }
    }

    private var expenseTotal: Double {
        filteredTransactions.filter { ($0.category?.type ?? .expense) == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var netTotal: Double {
        incomeTotal - expenseTotal
    }

    private var categoryStats: [CategoryStat] {
        let grouped = Dictionary(grouping: filteredTransactions) { $0.category?.name ?? "Uncategorized" }
        let periods = periodCount
        return grouped.compactMap { name, txs -> CategoryStat? in
            guard let first = txs.first else { return nil }
            let type = first.category?.type ?? .expense
            let total = txs.reduce(0) { $0 + $1.amount }
            let typeTotal = type == .income ? incomeTotal : expenseTotal
            return CategoryStat(
                id: first.category?.id.uuidString ?? name,
                name: name,
                colorHex: first.category?.colorHex ?? "#8E8E93",
                iconName: first.category?.iconName ?? "questionmark.circle",
                type: type,
                total: total,
                transactionCount: txs.count,
                avgPerTransaction: txs.isEmpty ? 0 : total / Double(txs.count),
                avgPerPeriod: total / Double(periods),
                percent: typeTotal > 0 ? total / typeTotal * 100 : 0
            )
        }
        .sorted {
            if $0.type != $1.type {
                return $0.type == .expense
            }
            if $0.total != $1.total {
                return $0.total > $1.total
            }
            return $0.name < $1.name
        }
    }

    private var periodCount: Int {
        let component: Calendar.Component
        switch granularity {
        case .daily: component = .day
        case .weekly: component = .weekOfMonth
        case .monthly: component = .month
        case .yearly: component = .year
        }
        let difference = Calendar.current.dateComponents([component], from: rangeStart, to: rangeEnd).value(for: component) ?? 0
        return max(1, difference + 1)
    }

    private var periodSuffix: String {
        switch granularity {
        case .daily: "day"
        case .weekly: "wk"
        case .monthly: "mo"
        case .yearly: "yr"
        }
    }

    private var selectedExpenseTotal: Double {
        selectedDetails.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var selectedIncomeTotal: Double {
        selectedDetails.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var selectedNetTotal: Double {
        selectedIncomeTotal - selectedExpenseTotal
    }

    private var selectedDetails: [CategoryBreakdown] {
        guard let selectedBucket else { return [] }
        let bucketTxs = filteredTransactions.filter { $0.date.start(of: granularity) == selectedBucket }
        let grouped = Dictionary(grouping: bucketTxs) { $0.category?.name ?? "Uncategorized" }

        return grouped.compactMap { name, txs -> CategoryBreakdown? in
            guard let first = txs.first else { return nil }
            return CategoryBreakdown(
                categoryName: name,
                colorHex: first.category?.colorHex ?? "#8E8E93",
                amount: txs.reduce(0) { $0 + $1.amount },
                type: first.category?.type ?? .expense
            )
        }
        .sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type == .expense
            }
            if lhs.type == .expense {
                return lhs.amount > rhs.amount
            }
            return lhs.amount < rhs.amount
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbarRow
                summaryHeader
                InsightsSection(insights: insightCards)
                chart

                if let bucket = selectedBucket, !selectedDetails.isEmpty {
                    bucketDetailCard(for: bucket)
                }

                switch activeTab {
                case .transactions:
                    transactionsBreakdownSection
                case .categories:
                    categoriesBreakdownSection
                case .balance:
                    balanceContent
                case .forecast:
                    forecastContent
                case .comparison:
                    comparisonContent
                case .patterns:
                    patternsContent
                }
            }
            .padding()
            .textSelection(.enabled)
        }
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 640)
        #endif
        .navigationTitle("Analytics")
        .animation(.default, value: activeTab)
    }

    private var balanceContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            BalanceChartSection(
                points: balancePoints,
                openingBalance: AnalyticsEngine.broughtForward(allTx: allTransactions, before: rangeStart)
            )
            HeatmapSection(rangeStart: rangeStart, rangeEnd: rangeEnd, dailyTotals: dailyHeatmapTotals)
        }
    }

    private var forecastContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let forecast = currentMonthForecast {
                ForecastSection(forecast: forecast)
            } else {
                ContentUnavailableView(
                    "No forecast yet",
                    systemImage: "wand.and.stars",
                    description: Text("Add transactions or recurring rules to the current month to see a projection.")
                )
            }
            budgetBoard
        }
    }

    private var comparisonContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeriodComparisonSection()
            RecurringSplitSection(
                committed: recurringSplit.committed,
                discretionary: recurringSplit.discretionary,
                ruleSpend: ruleSpend
            )
        }
    }

    private var patternsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpendPatternsSection(weekdaySpend: weekdaySpend, histogram: histogram, periodSuffix: periodSuffix)
        }
    }

    private var toolbarRow: some View {
        #if os(macOS)
            HStack(spacing: 10) {
                filtersButton
                rangeText
                Spacer()
                tabPicker
                granularityPicker
            }
        #else
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    filtersButton
                    Spacer()
                    rangeText
                }
                HStack {
                    compactTabMenu
                    Spacer()
                    compactGranularityMenu
                }
            }
        #endif
    }

    private var compactTabMenu: some View {
        Menu {
            Picker("Analytics view", selection: $activeTab) {
                ForEach(AnalyticsTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activeTab.icon)
                Text(activeTab.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Analytics view")
        .accessibilityHint(activeTab.label)
    }

    private var compactGranularityMenu: some View {
        Menu {
            Picker("Group by", selection: granularityBinding) {
                ForEach(Granularity.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(granularity.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Group by")
    }

    private var filtersButton: some View {
        Button {
            showFilters = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle\(hasActiveFilters ? ".fill" : "")")
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.2), value: hasActiveFilters)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                filtersContent
            }
        #else
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    ScrollView {
                        filtersContent
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showFilters = false
                            }
                        }
                    }
                    .navigationTitle("Filters")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        #endif
            .accessibilityLabel("Filters")
    }

    private var rangeText: some View {
        Text("\(rangeStart.formatted(style: .medium)) – \(rangeEnd.formatted(style: .medium))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var tabPicker: some View {
        Picker("Analytics view", selection: $activeTab) {
            ForEach(AnalyticsTab.allCases) { tab in
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.menu)
        #if os(macOS)
            .fixedSize()
        #endif
            .accessibilityLabel("Analytics view")
    }

    private var granularityPicker: some View {
        Picker("Group by", selection: granularityBinding) {
            ForEach(Granularity.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.menu)
        #if os(macOS)
            .fixedSize()
        #endif
            .accessibilityLabel("Group by")
    }

    private var filtersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Reset All") {
                    resetFilters()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tint)
                .disabled(!hasActiveFilters)
            }

            DatePicker("From", selection: fromDateBinding)
            DatePicker("To", selection: toDateBinding)

            #if os(macOS)
                HStack(spacing: 12) {
                    togglesRow
                    Spacer()
                    amountRangeRow
                }
            #else
                togglesRow
                amountRangeRow
            #endif

            Divider()

            categoryToggles
        }
        .padding(16)
        #if os(macOS)
            .frame(width: 430)
        #endif
    }

    private var togglesRow: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $showIncome) {
                Text("Income")
                    .foregroundStyle(.green)
            }
            .fixedSize()

            Toggle(isOn: $showExpense) {
                Text("Expenses")
                    .foregroundStyle(.red)
            }
            .fixedSize()
        }
    }

    private var amountRangeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Amount Range")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            AmountRangeSlider(
                bounds: ClosedRange.amountBounds(for: boundsTransactions.map(\.amount)),
                lowText: $minAmountText,
                highText: $maxAmountText
            )

            Text(amountRangeCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var amountRangeCaption: String {
        let bounds = ClosedRange.amountBounds(for: boundsTransactions.map(\.amount))
        let suffix = " (\(Int(bounds.lowerBound))–\(Int(bounds.upperBound)))"
        switch (minAmountText.isEmpty, maxAmountText.isEmpty) {
        case (true, true):
            return "Showing all amounts" + suffix
        case (false, true):
            return "From \(minAmountText) and up"
        case (true, false):
            return "Up to \(maxAmountText)"
        default:
            return "\(minAmountText) – \(maxAmountText)"
        }
    }

    private var boundsTransactions: [Transaction] {
        allTransactions.filter { $0.date >= rangeStart && $0.date <= rangeEnd }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(granularity.label) view")
                    .font(.title2.weight(.semibold))
                Text("\(filteredTransactions.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(netTotal.formattedCurrency)
                    .font(.title2.weight(.bold))
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("+")
                        Text(incomeTotal.formattedCurrency)
                    }
                    .foregroundStyle(.green)

                    HStack(spacing: 4) {
                        Text("−")
                        Text(expenseTotal.formattedCurrency)
                    }
                    .foregroundStyle(.red)
                }
                .font(.callout)
            }
        }

        deltaRow
    }

    private var deltaRow: some View {
        HStack(spacing: 14) {
            deltaBadge(label: "Income vs prev period", current: incomeTotal, previous: prevIncomeTotal)
            deltaBadge(label: "Expenses vs prev period", current: expenseTotal, previous: prevExpenseTotal)
            deltaBadge(label: "Net vs prev period", current: netTotal, previous: prevNetTotal)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func deltaBadge(label: String, current: Double, previous: Double) -> some View {
        if let delta = Self.percentDelta(current: current, previous: previous) {
            let up = delta > 0
            HStack(spacing: 3) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                Text("\(String(format: "%.0f", abs(delta)))%")
            }
            .foregroundStyle(
                label.contains("Expenses")
                    ? (up ? Color.red : .green)
                    : (up ? Color.green : .red)
            )
            .help("\(label): \(previous.formattedCurrency) → \(current.formattedCurrency)")
        }
    }

    @ViewBuilder
    private var chart: some View {
        if filteredTransactions.isEmpty {
            ContentUnavailableView(
                "No transactions in this range",
                systemImage: "chart.bar.xaxis",
                description: Text("Try widening the date range or relaxing filters.")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            dataChart
        }
    }

    private var monthsSpan: Int {
        let diff = Calendar.current.dateComponents([.month], from: rangeStart, to: rangeEnd).month ?? 0
        return max(1, diff + 1)
    }

    @ViewBuilder
    private var budgetBoard: some View {
        let budgets = budgetStats
        if !budgets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Budget Board")
                    .font(.headline)

                GroupBox {
                    VStack(spacing: 12) {
                        ForEach(budgets) { budget in
                            budgetRow(budget)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private struct BudgetStat: Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let limit: Double
        let avgPerMonth: Double
        let monthsOver: Int

        var percent: Double {
            limit > 0 ? avgPerMonth / limit * 100 : 0
        }
    }

    private var budgetStats: [BudgetStat] {
        var limits: [Category] = []
        for category in categories where category.type == .expense {
            if category.limit != nil {
                limits.append(category)
            }
        }

        let months = Double(monthsSpan)
        return limits.map { category in
            let total = filteredTransactions
                .filter { $0.category?.id == category.id && ($0.category?.type ?? .expense) == .expense }
                .reduce(0) { $0 + $1.amount }
            let avg = total / months

            var monthsOver = 0
            var cursor = rangeStart
            let calendar = Calendar.current
            while cursor <= rangeEnd {
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: cursor.startOfMonth) else { break }
                let monthTotal = filteredTransactions
                    .filter { $0.category?.id == category.id }
                    .filter { $0.date >= cursor && $0.date < monthEnd }
                    .reduce(0) { $0 + $1.amount }
                if category.limit.map({ monthTotal > $0 }) == true {
                    monthsOver += 1
                }
                cursor = monthEnd
            }

            return BudgetStat(
                id: category.id,
                name: category.name,
                colorHex: category.colorHex,
                limit: category.limit ?? 0,
                avgPerMonth: avg,
                monthsOver: monthsOver
            )
        }
        .sorted { $0.percent > $1.percent }
    }

    private func budgetRow(_ budget: BudgetStat) -> some View {
        let over = budget.avgPerMonth > budget.limit
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: budget.colorHex))
                    .frame(width: 8, height: 8)
                Text(budget.name)
                Spacer()
                Text("\(budget.avgPerMonth.formattedCurrency) / \(budget.limit.formattedCurrency)")
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(over ? .red : .primary)
                Text(String(format: "%.0f%%", min(budget.percent, 999)))
                    .monospacedDigit()
                    .foregroundStyle(over ? .red : .secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            ProgressView(value: min(max(budget.percent, 0), 100) / 100)
                .tint(over ? .red : Color(hex: budget.colorHex))

            if budget.monthsOver > 0 {
                Text("Over limit in \(budget.monthsOver) of \(monthsSpan) month(s) · avg over the range \(budget.avgPerMonth.formattedCurrency)/mo")
                    .font(.caption)
                    .foregroundStyle(over ? .red : .secondary)
            }
        }
        .font(.callout)
    }

    private var topTransactions: [Transaction] {
        Array(
            filteredTransactions
                .filter { ($0.category?.type ?? .expense) == .expense }
                .sorted { $0.amount > $1.amount }
                .prefix(3)
        )
    }

    private var dataChart: some View {
        Chart(chartData) { item in
            BarMark(
                x: .value("Period", item.bucket, unit: granularity.calendarComponent),
                y: .value("Amount", item.amount)
            )
            .foregroundStyle(by: .value("Category", item.categoryName))
            .accessibilityLabel("\(item.categoryName), \(item.bucket.periodLabel(for: granularity))")
            .accessibilityValue(item.amount.formattedCurrency)
        }
        .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(abs(amount).formattedCurrency)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onAppear { chartSize = geometry.size }
                    .onChange(of: geometry.size) { chartSize = $1 }
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let plotRect = proxy.plotFrame else { return }
                        let plotFrame = geometry[plotRect]
                        let point = CGPoint(
                            x: location.x - plotFrame.origin.x,
                            y: location.y - plotFrame.origin.y
                        )
                        guard point.x >= 0, point.x <= plotFrame.width, point.y >= 0, point.y <= plotFrame.height else {
                            selectedBucket = nil
                            return
                        }
                        if let bucket: Date = proxy.value(atX: point.x) {
                            selectedBucket = selectedBucket == bucket ? nil : bucket
                        } else {
                            selectedBucket = nil
                        }
                    }
            }
        }
        .frame(height: 320)
        .animation(.snappy(duration: 0.25), value: selectedBucket)
    }

    private func bucketDetailCard(for bucket: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bucket.periodLabel(for: granularity))
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    selectedBucket = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close detailed view")
            }

            ForEach(selectedDetails, id: \.categoryName) { detail in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: detail.colorHex))
                        .frame(width: 8, height: 8)
                    Text(detail.categoryName)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(detail.amount.formattedCurrency)
                        .fontWeight(.semibold)
                }
                .font(.caption)
            }

            Divider()

            if selectedIncomeTotal > 0 {
                HStack {
                    Text("Income").font(.caption).foregroundStyle(.green)
                    Spacer()
                    Text(selectedIncomeTotal.formattedCurrency)
                        .font(.caption).foregroundStyle(.green)
                }
            }
            if selectedExpenseTotal > 0 {
                HStack {
                    Text("Expenses").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Text(selectedExpenseTotal.formattedCurrency)
                        .font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Text("Net").font(.caption.weight(.bold))
                Spacer()
                Text(selectedNetTotal.formattedCurrency)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transactionsBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transactions")
                    .font(.headline)
                Spacer()
                Button {
                    sortAscending.toggle()
                } label: {
                    Label(sortAscending ? "Ascending" : "Descending", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Toggle sort order")
                .accessibilityLabel("Toggle sort order")
            }

            GroupBox {
                transactionsList
            }
        }
    }

    private var categoriesBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.headline)

            GroupBox {
                categoriesList
            }
        }
    }

    @ViewBuilder
    private var transactionsList: some View {
        if sortedTransactions.isEmpty {
            Text("No transactions for the selected filters.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                let topIDs = Set(topTransactions.map(\.id))
                if !topIDs.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "flame")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Biggest expense: \(topTransactions.first.map { "\($0.title) (\($0.amount.formattedCurrency))" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let avg = sortedTransactions.filter { ($0.category?.type ?? .expense) == .expense }.map(\.amount).averageOrZero
                        if avg > 0 {
                            Text("avg \(avg.formattedCurrency)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(sortedTransactions) { tx in
                    transactionRow(tx)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var categoriesList: some View {
        if categoryStats.isEmpty {
            Text("No data for the selected filters.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                categoryGroup("Expenses", stats: categoryStats.filter { $0.type == .expense })
                categoryGroup("Income", stats: categoryStats.filter { $0.type == .income })
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryGroup(_ title: String, stats: [CategoryStat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(title == "Income" ? Color.green : Color.red)

            if stats.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stats) { stat in
                    categoryRow(stat)
                }
            }
        }
    }

    private func categoryRow(_ stat: CategoryStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: stat.colorHex))
                    .frame(width: 8, height: 8)

                Image(systemName: stat.iconName)
                    .frame(width: 16)
                    .foregroundStyle(Color(hex: stat.colorHex))

                Text(stat.name)
                    .lineLimit(1)

                Spacer()

                Text(stat.total.formattedCurrency)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(stat.type == .income ? .green : .red)

                Text(String(format: "%.0f%%", stat.percent))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            ProgressView(value: min(stat.percent, 100) / 100)
                .tint(Color(hex: stat.colorHex))

            Text("\(stat.transactionCount) transactions · \(stat.avgPerTransaction.formattedCurrency) avg/tx · \(stat.avgPerPeriod.formattedCurrency) avg/\(periodSuffix)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .help("\(String(format: "%.1f", stat.percent))% of total \(stat.type == .income ? "income" : "expenses")")
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        let type = tx.category?.type ?? .expense
        let colorHex = tx.category?.colorHex ?? "#8E8E93"
        let isTop = topTransactions.contains { $0.id == tx.id }
        return HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)

            Image(systemName: tx.category?.iconName ?? "questionmark.circle")
                .frame(width: 16)
                .foregroundStyle(Color(hex: colorHex))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(tx.title.isEmpty ? "Untitled" : tx.title)
                        .lineLimit(1)
                    if isTop {
                        Text("TOP")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(tx.category?.name ?? "Uncategorized") · \(tx.date.formatted(style: .medium))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(type == .income ? "+" : "−")\(tx.amount.formattedCurrency)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(type == .income ? .green : .red)
        }
        .font(.callout)
    }

    private var categoryToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                if !selectedCategoryIDs.isEmpty {
                    Button("Show all") {
                        selectedCategoryIDs = []
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(categories) { category in
                    Toggle(isOn: categoryBinding(category)) {
                        Label(category.name, systemImage: category.iconName)
                            .foregroundStyle(Color(hex: category.colorHex))
                    }
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                }
            }
        }
    }

    private func categoryBinding(_ category: Category) -> Binding<Bool> {
        Binding {
            selectedCategoryIDs.isEmpty || selectedCategoryIDs.contains(category.id)
        } set: { isSelected in
            if selectedCategoryIDs.isEmpty {
                selectedCategoryIDs = Set(categories.map(\.id))
            }

            if isSelected {
                selectedCategoryIDs.insert(category.id)
            } else {
                selectedCategoryIDs.remove(category.id)
            }
        }
    }

    private func resetFilters() {
        fromDate = (Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now).startOfMonth
        toDate = .now
        showIncome = true
        showExpense = true
        minAmountText = ""
        maxAmountText = ""
        selectedCategoryIDs = []
    }
}

private struct BucketKey: Hashable {
    let bucket: Date
    let name: String
}
