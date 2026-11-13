import Foundation
import SwiftData

enum AnalyticsEngine {
    // MARK: Totals

    static func incomeTotal(_ txs: [Transaction]) -> Double {
        txs.filter { $0.category?.type == .income }.reduce(0) { $0 + $1.amount }
    }

    static func expenseTotal(_ txs: [Transaction]) -> Double {
        txs.filter { $0.category?.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    static func netTotal(_ txs: [Transaction]) -> Double {
        incomeTotal(txs) - expenseTotal(txs)
    }

    static func savingsRate(income: Double, net: Double) -> Double? {
        guard income > 0 else { return nil }
        return net / income * 100
    }

    static func percentDelta(current: Double, previous: Double) -> Double? {
        guard previous != 0 else { return nil }
        return (current - previous) / abs(previous) * 100
    }

    static func periodCount(from start: Date, to end: Date, granularity: Granularity) -> Int {
        let component = granularity.calendarComponent
        let difference = Calendar.current.dateComponents([component], from: start, to: end).value(for: component) ?? 0
        return max(1, difference + 1)
    }

    static func broughtForward(allTx: [Transaction], before start: Date) -> Double {
        let txTotal = allTx.filter { $0.date < start }.reduce(0) { $0 + $1.signedCashAmount }
        return txTotal + OpeningBalance.amount
    }

    // MARK: Balance over time

    struct BalancePoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
    }

    static func cumulativeBalanceSeries(allTx: [Transaction], rangeTx: [Transaction], rangeStart: Date, rangeEnd: Date) -> [BalancePoint] {
        let calendar = Calendar.current
        let startDay = rangeStart.startOfDay
        let endDay = rangeEnd.endOfDay
        guard startDay <= endDay else { return [] }

        var balance = broughtForward(allTx: allTx, before: startDay)
        var points: [BalancePoint] = [BalancePoint(date: startDay, balance: balance)]

        var cursor = startDay
        while cursor <= endDay {
            let dayEnd = cursor.endOfDay
            balance += rangeTx
                .filter { $0.date >= cursor && $0.date <= dayEnd }
                .reduce(0) { $0 + $1.signedCashAmount }
            points.append(BalancePoint(date: cursor, balance: balance))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    // MARK: Heatmap

    struct DailyAmount: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }

    static func dailyExpenseTotals(_ txs: [Transaction]) -> [DailyAmount] {
        let expenses = txs.filter { $0.category?.type == .expense }
        return Dictionary(grouping: expenses) { $0.date.startOfDay }
            .map { date, txs in DailyAmount(date: date, amount: txs.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }
    }

    static func weeklyExpenseTotals(_ txs: [Transaction]) -> [DailyAmount] {
        let expenses = txs.filter { $0.category?.type == .expense }
        return Dictionary(grouping: expenses) {
            Calendar.current.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date.startOfDay
        }
        .map { date, txs in DailyAmount(date: date, amount: txs.reduce(0) { $0 + $1.amount }) }
        .sorted { $0.date < $1.date }
    }

    // MARK: Period comparison

    struct CategoryDelta: Identifiable {
        var id: String {
            name
        }

        let name: String
        let colorHex: String
        let iconName: String
        let type: CategoryType
        let current: Double
        let previous: Double
        let percent: Double?
    }

    private static func categoryTotal(_ txs: [Transaction], type: CategoryType) -> Double {
        type == .investment ? txs.netInvested : txs.reduce(0) { $0 + $1.amount }
    }

    static func categoryDeltas(current: [Transaction], previous: [Transaction], categories: [Category]) -> [CategoryDelta] {
        var meta: [String: (colorHex: String, icon: String, type: CategoryType)] = [:]
        for category in categories {
            meta[category.name] = (category.colorHex, category.iconName, category.type)
        }
        let fallback = ("#8E8E93", "questionmark.circle", CategoryType.expense)

        let currentGrouped = Dictionary(grouping: current) { $0.category?.name ?? "Uncategorized" }
        let previousGrouped = Dictionary(grouping: previous) { $0.category?.name ?? "Uncategorized" }
        let names = Set(currentGrouped.keys).union(previousGrouped.keys)

        return names.map { name in
            let info = meta[name] ?? fallback
            let currentValue = categoryTotal(currentGrouped[name] ?? [], type: info.type)
            let previousValue = categoryTotal(previousGrouped[name] ?? [], type: info.type)
            return CategoryDelta(
                name: name,
                colorHex: info.colorHex,
                iconName: info.icon,
                type: info.type,
                current: currentValue,
                previous: previousValue,
                percent: percentDelta(current: currentValue, previous: previousValue)
            )
        }
        .sorted {
            if $0.type != $1.type {
                return $0.type.sortRank < $1.type.sortRank
            }
            if $0.current != $1.current {
                return $0.current > $1.current
            }
            return $0.name < $1.name
        }
    }

    // MARK: Insights

    struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let tintHex: String
        let title: String
        let detail: String
    }

    static func generateInsights(
        current: [Transaction],
        previous: [Transaction],
        categories: [Category],
        rangeStart: Date,
        rangeEnd: Date,
        granularity: Granularity
    ) -> [Insight] {
        var insights: [Insight] = []
        let income = incomeTotal(current)
        let expenses = expenseTotal(current)
        let net = income - expenses
        let prevIncome = incomeTotal(previous)
        let prevExpenses = expenseTotal(previous)
        let prevNet = prevIncome - prevExpenses

        if let rate = savingsRate(income: income, net: net) {
            insights.append(Insight(
                icon: rate >= 0 ? "banknote" : "exclamationmark.triangle",
                tintHex: rate >= 0 ? "#34C759" : "#FF3B30",
                title: "Savings rate \(String(format: "%.0f", max(rate, 0)))%",
                detail: rate >= 0
                    ? "You kept \(net.formattedCurrency) of \(income.formattedCurrency) earned in this range."
                    : "Spending exceeded income by \(abs(net).formattedCurrency) in this range."
            ))
        }

        if let delta = percentDelta(current: net, previous: prevNet) {
            let improved = delta > 0
            insights.append(Insight(
                icon: improved ? "arrow.up.forward" : "arrow.down.right",
                tintHex: improved ? "#34C759" : "#FF3B30",
                title: "Net \(improved ? "up" : "down") \(String(format: "%.0f", abs(delta)))%",
                detail: "\(prevNet.formattedCurrency) previous → \(net.formattedCurrency) now."
            ))
        }

        let expenseCategories = Dictionary(grouping: current.filter { $0.category?.type == .expense }) { $0.category?.name ?? "Uncategorized" }
        if let biggest = expenseCategories
            .map({ name, txs -> (String, Double) in (name, txs.reduce(0) { $0 + $1.amount }) })
            .max(by: { $0.1 < $1.1 }), expenses > 0
        {
            let percent = biggest.1 / expenses * 100
            let hex = categories.first { $0.name == biggest.0 }?.colorHex ?? "#FF9500"
            insights.append(Insight(
                icon: "crown",
                tintHex: hex,
                title: "Biggest expense: \(biggest.0)",
                detail: "\(biggest.1.formattedCurrency), \(String(format: "%.0f", percent))% of all spending."
            ))
        }

        let prevGrouped = Dictionary(grouping: previous.filter { $0.category?.type == .expense }) { $0.category?.name ?? "Uncategorized" }
        var swings: [(name: String, delta: Double, current: Double, previous: Double)] = []
        for (name, txs) in expenseCategories {
            let currentValue = txs.reduce(0) { $0 + $1.amount }
            guard let prevTx = prevGrouped[name] else { continue }
            let previousValue = prevTx.reduce(0) { $0 + $1.amount }
            guard let delta = percentDelta(current: currentValue, previous: previousValue) else { continue }
            swings.append((name, delta, currentValue, previousValue))
        }
        if let topIncrease = swings.filter({ $0.delta >= 20 }).max(by: { $0.delta < $1.delta }) {
            let hex = categories.first { $0.name == topIncrease.name }?.colorHex ?? "#FF3B30"
            insights.append(Insight(
                icon: "arrow.up.heart",
                tintHex: hex,
                title: "\(topIncrease.name) up \(String(format: "%.0f", topIncrease.delta))%",
                detail: "\(topIncrease.previous.formattedCurrency) previous → \(topIncrease.current.formattedCurrency) now."
            ))
        }
        if let topDecrease = swings.filter({ $0.delta <= -20 }).min(by: { $0.delta < $1.delta }) {
            let hex = categories.first { $0.name == topDecrease.name }?.colorHex ?? "#34C759"
            insights.append(Insight(
                icon: "arrow.down.heart",
                tintHex: hex,
                title: "\(topDecrease.name) down \(String(format: "%.0f", abs(topDecrease.delta)))%",
                detail: "\(topDecrease.previous.formattedCurrency) previous → \(topDecrease.current.formattedCurrency) now."
            ))
        }

        let currentAverages = expenseCategories.mapValues { $0.map(\.amount).averageOrZero }
        let prevCounts = prevGrouped.mapValues { $0.count }
        if let outlier = current
            .filter({ $0.category?.type == .expense })
            .compactMap({ tx -> Transaction? in
                guard let average = currentAverages[tx.category?.name ?? "Uncategorized"], average > 0 else { return nil }
                return tx.amount >= 3 * average ? tx : nil
            })
            .max(by: { $0.amount < $1.amount }),
            (prevCounts[outlier.category?.name ?? "Uncategorized"] ?? 0) >= 3
        {
            insights.append(Insight(
                icon: "sparkles",
                tintHex: "#AF52DE",
                title: "Unusual spend: \(outlier.title.isEmpty ? "Untitled" : outlier.title)",
                detail: "\(outlier.amount.formattedCurrency) is at least 3× your usual per-transaction spend in \(outlier.category?.name ?? "Uncategorized")."
            ))
        }

        if let largest = current.filter({ $0.category?.type == .expense }).max(by: { $0.amount < $1.amount }) {
            insights.append(Insight(
                icon: "flame",
                tintHex: "#FF9500",
                title: "Largest expense: \(largest.title.isEmpty ? "Untitled" : largest.title)",
                detail: "\(largest.amount.formattedCurrency) on \(largest.date.formatted(style: .medium))."
            ))
        }

        if granularity == .monthly {
            let periods = Double(periodCount(from: rangeStart, to: rangeEnd, granularity: granularity))
            let byCategory = Dictionary(grouping: current.filter { $0.category?.type == .expense }) { $0.category }
            if let overspend = byCategory
                .compactMap({ entry -> (Category, Double)? in
                    guard let limit = entry.0?.limit, limit > 0 else { return nil }
                    let average = entry.1.reduce(0) { $0 + $1.amount } / periods
                    return average > limit ? (entry.0!, average) : nil
                })
                .max(by: { $0.1 / ($0.0.limit ?? 1) < $1.1 / ($1.0.limit ?? 1) })
            {
                let percent = overspend.1 / (overspend.0.limit ?? 1) * 100
                insights.append(Insight(
                    icon: "gauge.with.dots.needle.67percent.exclamation",
                    tintHex: "#FF3B30",
                    title: "Budget pressure: \(overspend.0.name)",
                    detail: "Averaging \(overspend.1.formattedCurrency)/mo vs \(overspend.0.limit?.formattedCurrency ?? "") limit (\(String(format: "%.0f", percent))%)."
                ))
            }
        }

        return Array(insights.prefix(8))
    }

    // MARK: Forecast

    struct UpcomingOccurrence: Identifiable {
        let id: String
        let title: String
        let colorHex: String
        let date: Date
        let amount: Double
    }

    struct ForecastResult {
        let month: Date
        let daysElapsed: Int
        let daysInMonth: Int
        let committedSoFarNet: Double
        let committedRemainingNet: Double
        let discretionaryNetSoFar: Double
        let projectedNet: Double
        let projectedClosingBalance: Double
        let upcoming: [UpcomingOccurrence]
    }

    static func upcomingOccurrences(rules: [RecurringRule], until end: Date, after now: Date) -> [UpcomingOccurrence] {
        var occurrences: [UpcomingOccurrence] = []
        for rule in rules where rule.isActive {
            guard rule.amount > 0, let category = rule.category else { continue }
            var cursor = rule.lastGeneratedDate ?? rule.startDate
            var safety = 0
            while safety < 40 {
                safety += 1
                guard let next = rule.frequency.nextDate(after: cursor, dayNumber: rule.dayNumber) else { break }
                guard next > cursor, next <= end else { break }
                if let ruleEnd = rule.endDate, next > ruleEnd {
                    break
                }
                if next > now {
                    occurrences.append(UpcomingOccurrence(
                        id: "\(rule.id.uuidString)-\(next.timeIntervalSince1970)",
                        title: rule.title,
                        colorHex: category.colorHex,
                        date: next,
                        amount: category.type == .income ? rule.amount : -rule.amount
                    ))
                }
                cursor = next
            }
        }
        return occurrences.sorted { $0.date < $1.date }
    }

    static func forecast(month: Date, monthTxs: [Transaction], allTx: [Transaction], rules: [RecurringRule]) -> ForecastResult? {
        let calendar = Calendar.current
        let monthStart = month.startOfMonth
        let monthEnd = month.endOfMonth
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        let daysInMonth = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30

        let now = Date.now
        guard monthTxs.count > 0 || !rules.isEmpty else { return nil }

        let eligibleRules = rules.filter { rule in
            guard rule.isActive, rule.amount > 0, rule.category != nil else { return false }
            if let end = rule.endDate, end < now {
                return false
            }
            return rule.startDate <= monthEnd
        }
        let upcoming = upcomingOccurrences(rules: eligibleRules, until: monthEnd, after: now)

        let committedTxs = monthTxs.filter { $0.recurringRuleID != nil && $0.date <= now }
        let committedSoFarNet = committedTxs.reduce(0) { $0 + $1.signedCashAmount }
        let committedRemainingNet = upcoming.reduce(0) { $0 + $1.amount }
        let netSoFar = monthTxs.filter { $0.date <= now }.reduce(0) { $0 + $1.signedCashAmount }
        let discretionaryNetSoFar = netSoFar - committedSoFarNet

        let daysElapsed = max(1, calendar.dateComponents([.day], from: monthStart, to: now).day ?? 1)
        let committedProjected = committedSoFarNet + committedRemainingNet
        let discretionaryDaily = discretionaryNetSoFar / Double(daysElapsed)
        let projectedNet = committedProjected + discretionaryDaily * Double(daysInMonth)
        let projectedClosingBalance = broughtForward(allTx: allTx, before: monthStart) + projectedNet

        return ForecastResult(
            month: month,
            daysElapsed: daysElapsed,
            daysInMonth: daysInMonth,
            committedSoFarNet: committedSoFarNet,
            committedRemainingNet: committedRemainingNet,
            discretionaryNetSoFar: discretionaryNetSoFar,
            projectedNet: projectedNet,
            projectedClosingBalance: projectedClosingBalance,
            upcoming: upcoming
        )
    }

    // MARK: Recurring vs discretionary

    static func recurringExpenseShare(_ txs: [Transaction]) -> (committed: Double, discretionary: Double) {
        let expenses = txs.filter { $0.category?.type == .expense }
        let committed = expenses.filter { $0.recurringRuleID != nil }.reduce(0) { $0 + $1.amount }
        let discretionary = expenses.filter { $0.recurringRuleID == nil }.reduce(0) { $0 + $1.amount }
        return (committed, discretionary)
    }

    struct RuleSpend: Identifiable {
        let id = UUID()
        let title: String
        let colorHex: String
        let total: Double
        let count: Int

        var monthlyNormalized: Double {
            total
        }
    }

    static func recurringRuleSpend(_ txs: [Transaction], rules: [RecurringRule]) -> [RuleSpend] {
        let recurringTx = txs.filter { $0.recurringRuleID != nil && $0.category?.type == .expense }
        guard !recurringTx.isEmpty else { return [] }
        let grouped = Dictionary(grouping: recurringTx) { $0.recurringRuleID ?? UUID() }
        return grouped.compactMap { ruleID, txs in
            guard let rule = rules.first(where: { $0.id == ruleID }) else {
                return RuleSpend(title: txs.first?.category?.name ?? "Recurring", colorHex: txs.first?.category?.colorHex ?? "#8E8E93", total: txs.reduce(0) { $0 + $1.amount }, count: txs.count)
            }
            return RuleSpend(title: rule.title, colorHex: rule.category?.colorHex ?? "#8E8E93", total: txs.reduce(0) { $0 + $1.amount }, count: txs.count)
        }
        .sorted { $0.total > $1.total }
    }

    // MARK: Spend patterns

    struct WeekdaySpend: Identifiable {
        var id: Int {
            index
        }

        let index: Int
        let label: String
        let amount: Double
    }

    static func spendByWeekday(_ txs: [Transaction]) -> [WeekdaySpend] {
        let calendar = Calendar.current
        let expenses = txs.filter { $0.category?.type == .expense }
        let grouped = Dictionary(grouping: expenses) { calendar.component(.weekday, from: $0.date) }
        return (1 ... 7).map { weekday -> WeekdaySpend in
            let index = (weekday - calendar.firstWeekday + 7) % 7
            let label = calendar.shortWeekdaySymbols[(weekday - 1) % 7]
            return WeekdaySpend(index: index, label: label, amount: grouped[weekday]?.reduce(0) { $0 + $1.amount } ?? 0)
        }
        .sorted { $0.index < $1.index }
    }

    struct HistogramBucket: Identifiable {
        let id = UUID()
        let lower: Double
        let upper: Double
        let count: Int
        let total: Double

        var label: String {
            lower == 0
                ? "≤ \(upper.formattedCurrency)"
                : upper == .infinity
                ? "> \(lower.formattedCurrency)"
                : "\(lower.formattedCurrency) – \(upper.formattedCurrency)"
        }
    }

    static func expenseHistogram(_ txs: [Transaction], buckets: Int = 5) -> [HistogramBucket] {
        let amounts = txs.filter { $0.category?.type == .expense }.map(\.amount).filter { $0 >= 0 }
        guard !amounts.isEmpty else { return [] }
        let maxAmount = amounts.max() ?? 0
        guard maxAmount > 0 else {
            return [HistogramBucket(lower: 0, upper: 0, count: amounts.count, total: 0)]
        }
        let width = maxAmount / Double(buckets)
        var result: [HistogramBucket] = []
        for index in 0 ..< buckets {
            let lower = Double(index) * width
            let upper = index == buckets - 1 ? .infinity : Double(index + 1) * width
            let inBucket = amounts.filter { $0 >= lower && (index == buckets - 1 ? $0 <= maxAmount : $0 < upper) }
            result.append(HistogramBucket(lower: lower, upper: upper, count: inBucket.count, total: inBucket.reduce(0) { $0 + $1 }))
        }
        return result
    }

    // MARK: Repeat spending

    struct RepeatGroup: Identifiable {
        let id: String
        let title: String
        let categoryName: String
        let colorHex: String
        let iconName: String
        let count: Int
        let total: Double
        let average: Double
        let monthlyCost: Double
    }

    static func repeatSpending(_ txs: [Transaction], months: Int) -> [RepeatGroup] {
        let expenses = txs.filter { $0.category?.type == .expense }
        return Dictionary(grouping: expenses) { TransactionMatcher.normalizedTitle($0.title) }
            .compactMap { key, items -> RepeatGroup? in
                guard !key.isEmpty, items.count >= 2, let latest = items.max(by: { $0.date < $1.date }) else { return nil }
                let total = items.reduce(0) { $0 + $1.amount }
                return RepeatGroup(
                    id: key,
                    title: latest.title,
                    categoryName: latest.category?.name ?? "Uncategorized",
                    colorHex: latest.category?.colorHex ?? "#8E8E93",
                    iconName: latest.category?.iconName ?? "questionmark.circle",
                    count: items.count,
                    total: total,
                    average: total / Double(items.count),
                    monthlyCost: total / Double(max(1, months))
                )
            }
            .sorted { lhs, rhs in
                lhs.total != rhs.total ? lhs.total > rhs.total : lhs.id < rhs.id
            }
    }

    // MARK: Investments

    struct InvestmentFlow: Identifiable {
        var id: Date {
            bucket
        }

        let bucket: Date
        let contributions: Double
        let returns: Double
    }

    struct HoldingStat: Identifiable {
        let id: String
        let name: String
        let colorHex: String
        let iconName: String
        let contributed: Double
        let returned: Double
        let transactionCount: Int
        let lastActivity: Date?

        var netInvested: Double {
            contributed - returned
        }

        var returnRatio: Double? {
            guard contributed > 0 else { return nil }
            return returned / contributed * 100
        }
    }

    struct InvestedPoint: Identifiable {
        var id: Date {
            date
        }

        let date: Date
        let netInvested: Double
    }

    static func investmentFlows(_ txs: [Transaction], granularity: Granularity) -> [InvestmentFlow] {
        Dictionary(grouping: txs.filter(\.isInvestment)) { $0.date.start(of: granularity) }
            .map { bucket, items in
                InvestmentFlow(bucket: bucket, contributions: items.investmentContributions, returns: items.investmentReturns)
            }
            .sorted { $0.bucket < $1.bucket }
    }

    static func investmentHoldings(_ txs: [Transaction]) -> [HoldingStat] {
        Dictionary(grouping: txs.filter(\.isInvestment)) { $0.category?.id }
            .compactMap { _, items -> HoldingStat? in
                guard let category = items.first?.category else { return nil }
                return HoldingStat(
                    id: category.id.uuidString,
                    name: category.name,
                    colorHex: category.colorHex,
                    iconName: category.iconName,
                    contributed: items.investmentContributions,
                    returned: items.investmentReturns,
                    transactionCount: items.count,
                    lastActivity: items.map(\.date).max()
                )
            }
            .sorted {
                if $0.netInvested != $1.netInvested {
                    return $0.netInvested > $1.netInvested
                }
                return $0.name < $1.name
            }
    }

    static func cumulativeInvestedSeries(allTx: [Transaction], rangeStart: Date, rangeEnd: Date) -> [InvestedPoint] {
        let investments = allTx.filter(\.isInvestment)
        var running = investments.filter { $0.date < rangeStart }.netInvested
        var points = [InvestedPoint(date: rangeStart.startOfDay, netInvested: running)]
        let inRange = Dictionary(grouping: investments.filter { $0.date >= rangeStart && $0.date <= rangeEnd }) { $0.date.startOfDay }
        for day in inRange.keys.sorted() {
            running += inRange[day]?.netInvested ?? 0
            points.append(InvestedPoint(date: day, netInvested: running))
        }
        let endDay = min(rangeEnd, .now).startOfDay
        if let last = points.last, last.date < endDay {
            points.append(InvestedPoint(date: endDay, netInvested: running))
        }
        return points
    }
}
