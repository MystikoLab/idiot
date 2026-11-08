import Charts
import SwiftData
import SwiftUI

struct WeeklyChartView: View {
    let selectedMonth: Date
    let hiddenCategoryIDs: Set<Category.ID>
    let minAmount: Double?
    let maxAmount: Double?
    let showIncome: Bool
    let showExpense: Bool
    let showInvestment: Bool

    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        WeeklyChartContent(
            allTransactions: allTransactions,
            selectedMonth: selectedMonth,
            hiddenCategoryIDs: hiddenCategoryIDs,
            minAmount: minAmount,
            maxAmount: maxAmount,
            showIncome: showIncome,
            showExpense: showExpense,
            showInvestment: showInvestment
        )
        .onAppear {
            writeWidgetSnapshotIfCurrentMonth()
        }
        .onChange(of: allTransactions) {
            writeWidgetSnapshotIfCurrentMonth()
        }
    }

    private func writeWidgetSnapshotIfCurrentMonth() {
        guard Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month) else { return }
        WidgetSnapshotWriter.write(context: modelContext)
    }
}

private struct WeeklyChartContent: View {
    let selectedMonth: Date
    let showIncome: Bool
    let showExpense: Bool
    let showInvestment: Bool
    private let transactions: [Transaction]
    private let recurringTransactions: [Transaction]
    private let broughtForwardBalance: Double
    private let weeklyTotals: [WeeklyTotals]

    @AppStorage("weeklyChartSharedScale") private var sharedScale = false
    @State private var selectedWeekLabel: String?
    @State private var chartSize: CGSize = .zero
    @State private var yZoom: CGFloat = 1.0
    @State private var yPan: Double = 0.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var lastPan: Double = 0.0

    init(
        allTransactions: [Transaction],
        selectedMonth: Date,
        hiddenCategoryIDs: Set<Category.ID>,
        minAmount: Double?,
        maxAmount: Double?,
        showIncome: Bool,
        showExpense: Bool,
        showInvestment: Bool
    ) {
        self.selectedMonth = selectedMonth
        self.showIncome = showIncome
        self.showExpense = showExpense
        self.showInvestment = showInvestment

        let start = selectedMonth.startOfMonth
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? selectedMonth.endOfMonth
        var priorTotal = 0.0
        var monthTransactions: [Transaction] = []
        for tx in allTransactions {
            let date = tx.date
            if date < start {
                priorTotal += tx.signedCashAmount
            } else if date < end {
                monthTransactions.append(tx)
            }
        }
        broughtForwardBalance = priorTotal + OpeningBalance.amount
        recurringTransactions = monthTransactions.filter { $0.recurringRuleID != nil }

        let filtered = monthTransactions.filter { tx in
            if let cat = tx.category {
                if hiddenCategoryIDs.contains(cat.id) {
                    return false
                }
                if !showIncome, cat.type == .income {
                    return false
                }
                if !showExpense, cat.type == .expense {
                    return false
                }
                if !showInvestment, cat.type == .investment {
                    return false
                }
            }
            if let minVal = minAmount, tx.amount < minVal {
                return false
            }
            if let maxVal = maxAmount, tx.amount > maxVal {
                return false
            }
            return true
        }
        transactions = filtered

        let weekRange = Calendar.current.range(of: .weekOfMonth, in: .month, for: selectedMonth) ?? 1 ..< 1
        let byWeek = Dictionary(grouping: filtered) { $0.date.weekOfMonth }
        weeklyTotals = weekRange.map { week in
            let weekTxs = byWeek[week] ?? []
            return WeeklyTotals(
                week: week,
                weekLabel: Date.weekDateRangeLabel(weekNumber: week, in: selectedMonth),
                income: weekTxs.filter { $0.category?.type == .income }.reduce(0) { $0 + $1.amount },
                expense: weekTxs.filter { $0.category?.type == .expense }.reduce(0) { $0 + $1.amount },
                invested: weekTxs.netInvested
            )
        }
    }

    private var chartPoints: [WeeklyLinePoint] {
        let expenseScale = sharedScale ? sharedAxisMax : expenseAxisMax
        let incomeScale = sharedScale ? sharedAxisMax : incomeAxisMax
        let investmentScale = sharedScale ? sharedAxisMax : investmentAxisMax
        return weeklyTotals.flatMap { totals in
            var points: [WeeklyLinePoint] = []
            if showExpense {
                points.append(WeeklyLinePoint(
                    week: totals.week,
                    weekLabel: totals.weekLabel,
                    series: "Expenses",
                    amount: totals.expense,
                    normalized: totals.expense / expenseScale
                ))
            }
            if showIncome {
                points.append(WeeklyLinePoint(
                    week: totals.week,
                    weekLabel: totals.weekLabel,
                    series: "Income",
                    amount: totals.income,
                    normalized: totals.income / incomeScale
                ))
            }
            if showInvestment, hasInvestments {
                points.append(WeeklyLinePoint(
                    week: totals.week,
                    weekLabel: totals.weekLabel,
                    series: "Invested",
                    amount: totals.invested,
                    normalized: totals.invested / investmentScale
                ))
            }
            return points
        }
    }

    private var expenseAxisMax: Double {
        Self.niceAxisMax(weeklyTotals.map(\.expense).max() ?? 0)
    }

    private var incomeAxisMax: Double {
        Self.niceAxisMax(weeklyTotals.map(\.income).max() ?? 0)
    }

    private var sharedAxisMax: Double {
        var values: [Double] = []
        if showExpense {
            values += weeklyTotals.map(\.expense)
        }
        if showIncome {
            values += weeklyTotals.map(\.income)
        }
        if showInvestment {
            values += weeklyTotals.map { abs($0.invested) }
        }
        return Self.niceAxisMax(values.max() ?? 0)
    }

    private var investmentAxisMax: Double {
        Self.niceAxisMax(weeklyTotals.map { abs($0.invested) }.max() ?? 0)
    }

    private var seriesDomain: [String] {
        var series: [String] = []
        if showExpense {
            series.append("Expenses")
        }
        if showIncome {
            series.append("Income")
        }
        if showInvestment, hasInvestments {
            series.append("Invested")
        }
        return series
    }

    private static func seriesColor(_ series: String) -> Color {
        switch series {
        case "Expenses": .red
        case "Income": .green
        default: .investment
        }
    }

    private var hasInvestments: Bool {
        transactions.contains(where: \.isInvestment)
    }

    private var baseLowerBound: Double {
        min(0, chartPoints.map(\.normalized).min() ?? 0)
    }

    private static func niceAxisMax(_ value: Double) -> Double {
        guard value > 0 else { return 100 }
        let padded = value * 1.1
        let magnitude = pow(10, floor(log10(padded)))
        let fraction = padded / magnitude
        let step = [1.0, 2, 4, 6, 8, 10].first { fraction <= $0 } ?? 10
        return step * magnitude
    }

    private var axisTickValues: [Double] {
        let level = max(0, floor(log2(Double(yZoom))))
        let step = 0.25 / pow(2, level)
        let domain = yAxisDomain
        let first = (domain.lowerBound / step).rounded(.up)
        let last = (domain.upperBound / step).rounded(.down)
        guard first <= last else { return [] }
        return stride(from: first, through: last, by: 1).map { $0 * step }.filter { $0 >= 0 }
    }

    private var titleBlock: some View {
        HStack {
            Text("Weekly Overview")
                .font(.title2.weight(.semibold))
            Spacer(minLength: 8)
            scaleToggle
        }
    }

    private var scaleToggle: some View {
        Toggle(isOn: $sharedScale.animation(.snappy(duration: 0.3))) {
            Label("Same scale", systemImage: "ruler")
                .font(.caption.weight(.medium))
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(sharedScale ? "All lines share one scale. Click for separate scales." : "Each line has its own scale. Click to put them on one scale.")
        .accessibilityHint("Toggles whether income, expenses and investments share one axis")
    }

    private var netTile: some View {
        summaryTile("Net", value: monthlyNet.formattedCurrency, color: monthlyNet >= 0 ? .green : .red)
    }

    private var incomeTile: some View {
        summaryTile("Income", value: "+\(monthlyIncome.formattedCurrency)", color: .green)
    }

    private var expensesTile: some View {
        summaryTile("Expenses", value: "−\(monthlyExpenses.formattedCurrency)", color: .red)
    }

    private var investedTile: some View {
        summaryTile("Invested", value: monthlyInvested.formattedCurrency, color: .investment)
            .help("Contributions minus returns this month")
    }

    private var balanceTile: some View {
        summaryTile("Balance", value: totalBalance.formattedCurrency, color: balanceColor)
            .accessibilityHint("Includes \(broughtForwardBalance.formattedCurrency) brought forward")
            .help("Includes \(broughtForwardBalance.formattedCurrency) brought forward")
    }

    private var summaryTilesRow: some View {
        HStack(spacing: 8) {
            netTile
            incomeTile
            expensesTile
            if hasInvestments {
                investedTile
            }
            balanceTile
        }
    }

    private var summaryTiles: some View {
        Group {
            #if os(macOS)
                summaryTilesRow
            #else
                ViewThatFits(in: .horizontal) {
                    summaryTilesRow
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            netTile
                            balanceTile
                        }
                        GridRow {
                            incomeTile
                            expensesTile
                        }
                        if hasInvestments {
                            GridRow {
                                investedTile
                                    .gridCellColumns(2)
                            }
                        }
                    }
                }
            #endif
        }
        .textSelection(.enabled)
        .animation(.snappy(duration: 0.25), value: monthlyNet)
        .animation(.snappy(duration: 0.25), value: totalBalance)
    }

    private func summaryTile(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .maskedAmount()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Accessibility labels

    private var yAxisDomain: ClosedRange<Double> {
        let lower = baseLowerBound + yPan
        let span = (1.0 - baseLowerBound) / Double(yZoom)
        return lower ... (lower + span)
    }

    private var monthlyIncome: Double {
        transactions.filter { $0.category?.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var monthlyExpenses: Double {
        transactions.filter { $0.category?.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var monthlyNet: Double {
        monthlyIncome - monthlyExpenses
    }

    private var monthlyInvested: Double {
        transactions.netInvested
    }

    private var totalBalance: Double {
        broughtForwardBalance + monthlyNet - monthlyInvested
    }

    private var recurringCount: Int {
        recurringTransactions.count
    }

    private var recurringExpense: Double {
        recurringTransactions.filter { $0.category?.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var recurringIncome: Double {
        recurringTransactions.filter { $0.category?.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var balanceColor: Color {
        if totalBalance > 0 {
            return .green
        }

        if totalBalance < 0 {
            return .red
        }

        return .primary
    }

    private var selectedExpensesTotal: Double {
        selectedWeekDetails.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var selectedIncomeTotal: Double {
        selectedWeekDetails.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var selectedInvestedTotal: Double {
        selectedWeekDetails.filter { $0.type == .investment }.reduce(0) { $0 + $1.amount }
    }

    private var selectedNetTotal: Double {
        selectedIncomeTotal - selectedExpensesTotal
    }

    private var selectedWeekNumber: Int? {
        guard let selectedWeekLabel else { return nil }
        return weeklyTotals.first(where: { $0.weekLabel == selectedWeekLabel })?.week
    }

    private var selectedWeekDetails: [CategoryBreakdown] {
        guard let week = selectedWeekNumber else { return [] }
        let weekTxs = transactions.filter { $0.date.weekOfMonth == week }
        let grouped = Dictionary(grouping: weekTxs) { $0.category?.name ?? "Uncategorized" }

        return grouped.compactMap { name, txs in
            guard let category = txs.first?.category else { return nil }
            return CategoryBreakdown(
                categoryName: name,
                colorHex: category.colorHex,
                amount: category.type == .investment ? txs.netInvested : txs.reduce(0) { $0 + $1.amount },
                type: category.type
            )
        }
        .sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type.sortRank < rhs.type.sortRank
            }
            if lhs.type == .expense {
                return lhs.amount > rhs.amount
            }
            return lhs.amount < rhs.amount
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryTiles
            titleBlock
                .padding(.top, 6)

            if recurringCount > 0 {
                Text([
                    "\(recurringCount) recurring",
                    recurringExpense > 0 ? "−\(recurringExpense.formattedCurrency)" : nil,
                    recurringIncome > 0 ? "+\(recurringIncome.formattedCurrency)" : nil,
                ]
                .compactMap { $0 }
                .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .maskedAmount()
            }

            Chart(chartPoints) { point in
                LineMark(
                    x: .value("Week", point.weekLabel),
                    y: .value("Amount", point.normalized),
                    series: .value("Type", point.series)
                )
                .foregroundStyle(by: .value("Type", point.series))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Week", point.weekLabel),
                    y: .value("Amount", point.normalized)
                )
                .foregroundStyle(by: .value("Type", point.series))
                .symbolSize(selectedWeekLabel == point.weekLabel ? 80 : 30)
                .accessibilityLabel("\(point.series), week \(point.week)")
                .accessibilityValue(point.amount.formattedCurrency)

                if baseLowerBound < 0 {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }

                if let selectedWeekLabel, selectedWeekLabel == point.weekLabel {
                    RuleMark(x: .value("Week", selectedWeekLabel))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartForegroundStyleScale(domain: seriesDomain, range: seriesDomain.map(Self.seriesColor))
            .chartYScale(domain: yAxisDomain)
            .chartYAxis {
                if sharedScale {
                    AxisMarks(position: .leading, values: axisTickValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let fraction = value.as(Double.self) {
                                Text((fraction * sharedAxisMax).formattedCurrency)
                                    .maskedAmount()
                            }
                        }
                    }
                } else if showExpense {
                    AxisMarks(position: .leading, values: axisTickValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let fraction = value.as(Double.self) {
                                Text((fraction * expenseAxisMax).formattedCurrency)
                                    .foregroundStyle(.red)
                                    .maskedAmount()
                            }
                        }
                    }
                }
                if !sharedScale, showIncome {
                    AxisMarks(position: .trailing, values: axisTickValues) { value in
                        if !showExpense {
                            AxisGridLine()
                        }
                        AxisValueLabel {
                            if let fraction = value.as(Double.self) {
                                Text((fraction * incomeAxisMax).formattedCurrency)
                                    .foregroundStyle(.green)
                                    .maskedAmount()
                            }
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
                                selectedWeekLabel = nil
                                return
                            }
                            if let label: String = proxy.value(atX: point.x) {
                                selectedWeekLabel = selectedWeekLabel == label ? nil : label
                            } else {
                                selectedWeekLabel = nil
                            }
                        }
                }
            }
            #if os(macOS)
            .padding(.vertical, 8)
            .frame(minHeight: 280, maxHeight: .infinity)
            #else
            .padding(.vertical, 8)
            .frame(height: 320)
            #endif
            .clipped()
            #if os(macOS)
                .overlay(alignment: .topLeading) {
                    if selectedWeekNumber != nil, !selectedWeekDetails.isEmpty,
                       let label = selectedWeekLabel
                    {
                        weekDetailCard(label)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .frame(width: 260)
                            .padding(6)
                    }
                }
                .background(ScrollWheelHandler { delta in
                    let factor = exp(delta * 0.02)
                    yZoom = max(1.0, yZoom * factor)
                    lastZoom = yZoom
                })
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            yZoom = max(1.0, lastZoom * value)
                        }
                        .onEnded { _ in
                            lastZoom = yZoom
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            let span = (1.0 - baseLowerBound) / Double(yZoom)
                            let chartH = max(chartSize.height, 320)
                            yPan = lastPan + Double(value.translation.height) / Double(chartH) * span
                        }
                        .onEnded { _ in
                            lastPan = yPan
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { resetYZoom() }
                )
                .overlay(alignment: .topTrailing) {
                    if yZoom > 1.01 || abs(yPan) > 0.01 {
                        Button {
                            resetYZoom()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Reset zoom")
                        .padding(6)
                    }
                }
            #endif

            #if os(iOS)
                if selectedWeekNumber != nil, !selectedWeekDetails.isEmpty,
                   let label = selectedWeekLabel
                {
                    weekDetailCard(label)
                }
            #endif
        }
        .animation(.snappy(duration: 0.25), value: selectedWeekLabel)
        .padding(16)
        #if os(macOS)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        #else
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        #endif
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func weekDetailCard(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    selectedWeekLabel = nil
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

            ForEach(selectedWeekDetails, id: \.categoryName) { detail in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: detail.colorHex))
                        .frame(width: 8, height: 8)
                    Text(detail.categoryName)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(detail.amount.formattedCurrency)
                        .fontWeight(.semibold)
                        .maskedAmount()
                }
                .font(.caption)
            }

            Divider()
            if selectedExpensesTotal > 0 {
                HStack {
                    Text("Expenses").font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Text(selectedExpensesTotal.formattedCurrency)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .maskedAmount()
                }
            }
            if selectedInvestedTotal != 0 {
                HStack {
                    Text("Invested").font(.caption)
                        .foregroundStyle(Color.investment)
                    Spacer()
                    Text(selectedInvestedTotal.formattedCurrency)
                        .font(.caption)
                        .foregroundStyle(Color.investment)
                        .maskedAmount()
                }
            }
            if selectedIncomeTotal > 0 {
                HStack {
                    Text("Income").font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Text(selectedIncomeTotal.formattedCurrency)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .maskedAmount()
                }
            }
            HStack {
                Text("Net").font(.caption.weight(.bold))
                Spacer()
                Text(selectedNetTotal.formattedCurrency)
                    .font(.caption.weight(.bold))
                    .maskedAmount()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resetYZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            yZoom = 1.0
            yPan = 0.0
            lastZoom = 1.0
            lastPan = 0.0
        }
    }
}

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct WeeklyTotals {
    let week: Int
    let weekLabel: String
    let income: Double
    let expense: Double
    let invested: Double
}

struct WeeklyLinePoint: Identifiable {
    var id: String {
        "\(series)-\(week)"
    }

    let week: Int
    let weekLabel: String
    let series: String
    let amount: Double
    let normalized: Double
}

struct CategoryBreakdown {
    let categoryName: String
    let colorHex: String
    let amount: Double
    let type: CategoryType
}

#if os(macOS)
    struct ScrollWheelHandler: NSViewRepresentable {
        let onScroll: (CGFloat) -> Void

        func makeNSView(context _: Context) -> NSView {
            let view = _ScrollWheelView()
            view.onScroll = onScroll
            return view
        }

        func updateNSView(_ nsView: NSView, context _: Context) {
            (nsView as? _ScrollWheelView)?.onScroll = onScroll
        }
    }

    final class _ScrollWheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            wantsRestingTouches = true
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
        }
    }
#endif
