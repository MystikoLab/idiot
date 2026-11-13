import SwiftUI
import WidgetKit

struct StaticEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StaticProvider: TimelineProvider {
    func placeholder(in _: Context) -> StaticEntry {
        StaticEntry(date: .now, snapshot: WidgetStore.load())
    }

    func getSnapshot(in _: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now, snapshot: WidgetStore.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.load()
        var entries = [StaticEntry(date: now, snapshot: snapshot)]
        if let logged = snapshot.lastLogged {
            let feedbackEnd = logged.date.addingTimeInterval(WidgetStore.feedbackDuration)
            if feedbackEnd > now {
                entries.append(StaticEntry(date: feedbackEnd, snapshot: snapshot))
            }
        }
        let nextMonth = Calendar.current.dateInterval(of: .month, for: now)?.end ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: entries, policy: .after(nextMonth)))
    }
}

enum WidgetLink {
    static let add = URL(string: "idiot://add")
    static let open = URL(string: "idiot://open")
    static let analytics = URL(string: "idiot://analytics")
    static let goals = URL(string: "idiot://goals")
}

struct AddLink: View {
    var size: Font = .title2

    var body: some View {
        if let url = WidgetLink.add {
            Link(destination: url) {
                Image(systemName: "plus.circle.fill")
                    .font(size)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            }
            .accessibilityLabel("Add transaction")
        }
    }
}

private struct SegmentStyle {
    let renderingMode: WidgetRenderingMode

    func color(_ segment: SnapshotCategorySpend, at index: Int) -> Color {
        if renderingMode == .fullColor {
            return Color(snapshotHex: segment.colorHex)
        }
        return Color.primary.opacity(max(0.25, 1 - Double(index) * 0.13))
    }
}

struct SpendingBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let segments: [SnapshotCategorySpend]
    var height: CGFloat = 12

    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            if segments.isEmpty {
                Capsule()
                    .fill(.quaternary)
            } else {
                let widths = Self.widths(
                    for: segments.map(\.amount),
                    total: proxy.size.width,
                    gap: gap,
                    minimum: max(4, height * 0.5)
                )
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        UnevenRoundedRectangle(cornerRadii: radii(at: index), style: .continuous)
                            .fill(SegmentStyle(renderingMode: renderingMode).color(segment, at: index))
                            .frame(width: widths[index])
                    }
                }
            }
        }
        .frame(height: height)
        .widgetAccentable()
        .accessibilityHidden(true)
    }

    private func radii(at index: Int) -> RectangleCornerRadii {
        let end = height / 2
        let inner = min(2, height / 4)
        let leading = index == 0 ? end : inner
        let trailing = index == segments.count - 1 ? end : inner
        return RectangleCornerRadii(
            topLeading: leading,
            bottomLeading: leading,
            bottomTrailing: trailing,
            topTrailing: trailing
        )
    }

    static func widths(for amounts: [Double], total: CGFloat, gap: CGFloat, minimum: CGFloat) -> [CGFloat] {
        let count = amounts.count
        guard count > 0 else { return [] }
        let available = max(total - gap * CGFloat(count - 1), 0)
        let sum = amounts.reduce(0, +)
        guard sum > 0, available > minimum * CGFloat(count) else {
            return Array(repeating: available / CGFloat(count), count: count)
        }

        var widths = amounts.map { CGFloat($0 / sum) * available }
        var pinned = Set<Int>()
        while true {
            let small = widths.indices.filter { !pinned.contains($0) && widths[$0] < minimum }
            guard !small.isEmpty else { break }
            pinned.formUnion(small)
            let free = available - minimum * CGFloat(pinned.count)
            let freeSum = amounts.indices.filter { !pinned.contains($0) }.reduce(0) { $0 + amounts[$1] }
            guard freeSum > 0 else { break }
            for index in widths.indices {
                widths[index] = pinned.contains(index) ? minimum : CGFloat(amounts[index] / freeSum) * free
            }
        }
        return widths
    }
}

private struct LegendEntry: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let segment: SnapshotCategorySpend
    let index: Int
    var font: Font = .caption2
    var share: Double?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(SegmentStyle(renderingMode: renderingMode).color(segment, at: index))
                .frame(width: 7, height: 7)
                .widgetAccentable()
            Text(segment.name.isEmpty ? "Untitled" : segment.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let share {
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Text(segment.amount.widgetCurrency)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
                .privacySensitive()
        }
        .font(font)
        .accessibilityElement(children: .combine)
    }
}

private struct SpendingLegend: View {
    let segments: [SnapshotCategorySpend]
    var columns = 1
    var limit = 4
    var font: Font = .caption2
    var total: Double?
    var spacing: CGFloat = 4

    private var indexed: [(index: Int, segment: SnapshotCategorySpend)] {
        segments.prefix(limit).enumerated().map { (index: $0.offset, segment: $0.element) }
    }

    private var rows: [[(index: Int, segment: SnapshotCategorySpend)]] {
        let items = indexed
        return stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< min($0 + columns, items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows, id: \.first?.index) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.index) { item in
                        LegendEntry(
                            segment: item.segment,
                            index: item.index,
                            font: font,
                            share: total.flatMap { $0 > 0 ? item.segment.amount / $0 : nil }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    if row.count < columns {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}

private struct SpentTotal: View {
    let amount: Double
    var style: Font.TextStyle = .title2

    var body: some View {
        Text(amount.widgetCurrency)
            .font(.system(style, design: .rounded, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .privacySensitive()
    }
}

private struct SnapshotRowView: View {
    let row: SnapshotRow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.iconName)
                .font(.caption2)
                .foregroundStyle(Color(snapshotHex: row.colorHex))
                .frame(width: 16)
                .widgetAccentable()
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(row.isIncome ? "+" : "−")\(row.amount.widgetCurrency)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(row.isIncome ? Color.green : Color.primary)
                .lineLimit(1)
                .layoutPriority(1)
                .privacySensitive()
        }
    }
}

struct TransactionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TransactionWidget", provider: StaticProvider()) { entry in
            TransactionWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Transactions")
        .description("This month's spending and your most recent transactions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TransactionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StaticEntry

    private var snapshot: WidgetSnapshot {
        entry.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            header
            SpendingBar(segments: snapshot.spendSegments, height: 6)
            if snapshot.rows.isEmpty {
                Text("No transactions this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if family == .systemLarge {
                        ViewThatFits(in: .vertical) {
                            rows(8)
                            rows(6)
                            rows(5)
                        }
                    } else {
                        ViewThatFits(in: .vertical) {
                            rows(3)
                            rows(2)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.open)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Spent in \(snapshot.monthName)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SpentTotal(amount: snapshot.expense, style: family == .systemLarge ? .title2 : .title3)
            }
            Spacer(minLength: 8)
            Text("+\(snapshot.income.widgetCurrency)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
                .accessibilityLabel("Income \(snapshot.income.widgetCurrency)")
        }
    }

    private func rows(_ limit: Int) -> some View {
        VStack(spacing: family == .systemLarge ? 9 : 5) {
            ForEach(snapshot.rows.prefix(limit)) { row in
                SnapshotRowView(row: row)
            }
        }
    }
}

struct AnalyticsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnalyticsWidget", provider: StaticProvider()) { entry in
            AnalyticsWidgetView(entry: entry)
        }
        .configurationDisplayName("Monthly Spending")
        .description("What you have spent this month, split by category.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct AnalyticsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StaticEntry

    private var snapshot: WidgetSnapshot {
        entry.snapshot
    }

    private var segments: [SnapshotCategorySpend] {
        snapshot.spendSegments
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemLarge:
                largeView
            default:
                mediumView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(family == .systemSmall ? WidgetLink.add : WidgetLink.analytics)
        .containerBackground(.background, for: .widget)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.monthName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    SpentTotal(amount: snapshot.expense, style: .title3)
                }
                Spacer(minLength: 2)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                    .accessibilityLabel("Add transaction")
            }
            Spacer(minLength: 0)
            SpendingBar(segments: segments, height: 10)
            if segments.isEmpty {
                emptyLabel
            } else {
                SpendingLegend(segments: segments, limit: 2)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(style: .title2)
            Spacer(minLength: 0)
            SpendingBar(segments: segments, height: 12)
            if segments.isEmpty {
                emptyLabel
            } else {
                SpendingLegend(segments: segments, columns: 2, limit: 4)
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(style: .title)
            SpendingBar(segments: segments, height: 14)
            if segments.isEmpty {
                emptyLabel
            } else {
                SpendingLegend(segments: segments, limit: 7, font: .caption, total: snapshot.expense, spacing: 7)
            }
            Spacer(minLength: 0)
            Divider()
            footer
        }
    }

    private func header(style: Font.TextStyle) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Spent in \(snapshot.monthName)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SpentTotal(amount: snapshot.expense, style: style)
            }
            Spacer(minLength: 8)
            AddLink()
        }
    }

    private var emptyLabel: some View {
        Text("Nothing spent yet")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            stat("Income", value: "+\(snapshot.income.widgetCurrency)", color: .green)
            stat("Net", value: snapshot.net.widgetCurrency, color: snapshot.net >= 0 ? .green : .red)
            Spacer(minLength: 4)
            if snapshot.overLimitCount > 0 {
                Label(
                    snapshot.overLimitCount == 1 ? "1 category over budget" : "\(snapshot.overLimitCount) categories over budget",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else if let name = snapshot.topCategoryName {
                Text("Top: \(name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func stat(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
        }
    }
}

struct NewTransactionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NewTransactionWidget", provider: StaticProvider()) { entry in
            NewTransactionWidgetView(entry: entry)
        }
        .configurationDisplayName("New Transaction")
        .description("Opens the app on the new transaction form.")
        .supportedFamilies(NewTransactionWidgetFamilies.list)
    }
}

private enum NewTransactionWidgetFamilies {
    #if os(macOS)
        static let list: [WidgetFamily] = [.systemSmall]
    #else
        static let list: [WidgetFamily] = [.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #endif
}

private struct NewTransactionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StaticEntry

    var body: some View {
        content
            .widgetURL(WidgetLink.add)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Add transaction")
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label("New transaction", systemImage: "plus.circle.fill")
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .widgetAccentable()
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("New transaction")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Tap to add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.clear, for: .widget)
        default:
            homeScreenView
        }
    }

    private var homeScreenView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text("New")
                .font(.headline)
            Text("Transaction")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }
}

struct SavingsGoalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SavingsGoalsWidget", provider: StaticProvider()) { entry in
            SavingsGoalsWidgetView(entry: entry)
        }
        .configurationDisplayName("Savings Goals")
        .description("Progress towards your savings goals.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SavingsGoalsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StaticEntry

    private var goals: [SnapshotGoal] {
        entry.snapshot.goals ?? []
    }

    var body: some View {
        Group {
            if goals.isEmpty {
                emptyState
            } else if family == .systemSmall, let goal = goals.first {
                smallView(goal)
            } else {
                mediumView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.goals)
        .containerBackground(.background, for: .widget)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "target")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No goals yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func amounts(_ goal: SnapshotGoal) -> String {
        "\(goal.saved.widgetCurrency) of \(goal.target.widgetCurrency)"
    }

    private func smallView(_ goal: SnapshotGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: goal.iconName)
                    .font(.caption2)
                    .foregroundStyle(Color(snapshotHex: goal.colorHex))
                    .widgetAccentable()
                Text(goal.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            ZStack {
                Circle()
                    .stroke(goal.tint.opacity(0.2), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: goal.fraction)
                    .stroke(goal.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Text("\(goal.percent)%")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(amounts(goal))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(goal.name), \(goal.percent) percent, \(goal.statusLabel)")
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Savings Goals")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(goals.prefix(3)) { goal in
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: goal.iconName)
                            .font(.caption2)
                            .foregroundStyle(Color(snapshotHex: goal.colorHex))
                            .frame(width: 16)
                            .widgetAccentable()
                        Text(goal.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(goal.isReached ? goal.statusLabel : amounts(goal))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .privacySensitive(!goal.isReached)
                    }
                    Capsule()
                        .fill(goal.tint.opacity(0.2))
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(goal.tint)
                                    .frame(width: max(5, proxy.size.width * goal.fraction))
                                    .widgetAccentable()
                            }
                        }
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
