import SwiftUI

struct HeatmapSection: View {
    let rangeStart: Date
    let rangeEnd: Date
    let dailyTotals: [AnalyticsEngine.DailyAmount]

    private struct Cell: Identifiable {
        let id: Date
        let date: Date
        let amount: Double
        let isBlank: Bool
    }

    private struct Column: Identifiable {
        let id: Date
        let label: String?
        let cells: [Cell]
    }

    private struct IndexedColumn: Identifiable {
        let index: Int
        let column: Column

        var id: Date {
            column.id
        }
    }

    private var daysSpan: Int {
        Int(rangeEnd.timeIntervalSince(rangeStart) / 86400)
    }

    private var isDailyMode: Bool {
        daysSpan <= 210
    }

    private var totals: [(date: Date, amount: Double)] {
        if isDailyMode {
            return dailyTotals.map { ($0.date, $0.amount) }
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dailyTotals) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date.startOfDay
        }
        return grouped.map { date, items in (date, items.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }
    }

    private var stackedColor: Color {
        Color(hex: "#34C759")
    }

    private var levels: [Double] {
        let positive = totals.map(\.amount).filter { $0 > 0 }.sorted()
        guard positive.count >= 3 else {
            return [(positive.max() ?? 0) / 2, (positive.max() ?? 0) * 0.8, positive.max() ?? 0]
        }
        let fifty = positive[positive.count / 2]
        let ninety = positive[min(positive.count - 1, positive.count * 9 / 10)]
        let maximum = positive.max() ?? 0
        return [fifty, ninety, maximum]
    }

    private func levelColor(_ amount: Double) -> Color {
        guard amount > 0 else {
            return Color.primary.opacity(0.12)
        }
        let thresholds = levels
        if amount >= thresholds[2] {
            return stackedColor
        }
        if amount >= thresholds[1] {
            return stackedColor.opacity(0.75)
        }
        if amount >= thresholds[0] {
            return stackedColor.opacity(0.5)
        }
        return stackedColor.opacity(0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isDailyMode ? "Daily Spend Heatmap" : "Weekly Spend Heatmap")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 10, height: 10)
                    ForEach([levels[0], levels[1], levels[2]], id: \.self) { threshold in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stackedColor.opacity(threshold == levels[0] ? 0.5 : threshold == levels[1] ? 0.75 : 1))
                            .frame(width: 10, height: 10)
                    }
                    Text("More")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                if totals.isEmpty {
                    Text("No spending recorded in this range.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    horizontalGrid
                }
            }
        }
    }

    private var columns: [Column] {
        let calendar = Calendar.current
        let lookup = Dictionary(totals.map { ($0.date.timeIntervalSince1970, $0.amount) }, uniquingKeysWith: { first, _ in first })
        var result: [Column] = []

        if isDailyMode {
            let first = rangeStart.startOfDay
            let last = rangeEnd.endOfDay
            let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
            let leadingBlanks = (0 ..< offset).map { index in
                Cell(id: Date(timeIntervalSince1970: -86400 * Double(index + 1)), date: first, amount: 0, isBlank: true)
            }
            var pending: [Cell] = leadingBlanks
            var drift = offset

            var cursor = first
            while cursor <= last {
                let amount = lookup[cursor.startOfDay.timeIntervalSince1970] ?? 0
                pending.append(Cell(id: cursor, date: cursor, amount: amount, isBlank: false))
                drift += 1

                if drift == 7 {
                    result.append(Column(id: pending.first?.id ?? cursor, label: nil, cells: pending))
                    pending = []
                    drift = 0
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            if !pending.isEmpty {
                result.append(Column(id: pending.first?.id ?? last, label: nil, cells: pending))
            }
        } else {
            for (index, entry) in totals.enumerated() {
                let previous = index > 0 ? totals[index - 1].date : nil
                let showLabel = previous.map { !Calendar.current.isDate($0, equalTo: entry.date, toGranularity: .month) } ?? true
                result.append(
                    Column(
                        id: entry.date,
                        label: showLabel ? entry.date.formatted(.dateTime.month(.abbreviated)) : nil,
                        cells: [Cell(id: entry.date, date: entry.date, amount: entry.amount, isBlank: false)]
                    )
                )
            }
        }
        return result
    }

    private func monthLabelForDaily() -> [(columnIndex: Int, label: String)] {
        let calendar = Calendar.current
        var labels: [(columnIndex: Int, label: String)] = []
        var previousMonth = -1
        for (index, column) in columns.enumerated() {
            let firstReal = column.cells.first { !$0.isBlank }
            guard let day = firstReal?.date else { continue }
            let month = calendar.component(.month, from: day)
            if month != previousMonth {
                labels.append((index, day.formatted(.dateTime.month(.abbreviated))))
                previousMonth = month
            }
        }
        return labels
    }

    private var horizontalGrid: some View {
        let symbols = orderedWeekdaySymbols(Calendar.current)
        let columns = columns
        let indexedColumns = columns.enumerated().map { IndexedColumn(index: $0.offset, column: $0.element) }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(symbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 14, alignment: .trailing)
                    }
                }
                .padding(.top, 14)
                .opacity(isDailyMode ? 1 : 0)

                ForEach(indexedColumns) { item in
                    columnView(item.index, column: item.column)
                }
            }
            .padding(.bottom, isDailyMode ? 4 : 18)
        }
    }

    private func cellView(_ cell: Cell) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(levelColor(cell.amount))
            .frame(width: 16, height: 16)
            .help("Week of \(cell.date.formatted(style: .medium)) · \(cell.amount.formattedCurrency)")
    }

    private func columnView(_ index: Int, column: Column) -> some View {
        let dailyLabels = isDailyMode ? monthLabelForDaily() : []
        let hasLabel = isDailyMode ? dailyLabels.contains { $0.columnIndex == index } : column.label != nil
        let labelText = isDailyMode ? (dailyLabels.first { $0.columnIndex == index }?.label ?? " ") : (column.label ?? " ")
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"

        return VStack(alignment: .center, spacing: 3) {
            Text(labelText)
                .font(.system(size: 8))
                .foregroundStyle(hasLabel ? Color.secondary : Color.clear)
                .frame(height: 12)

            if isDailyMode {
                VStack(spacing: 3) {
                    ForEach(column.cells) { cell in
                        if cell.isBlank {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.clear)
                                .frame(width: 14, height: 14)
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(levelColor(cell.amount))
                                .frame(width: 14, height: 14)
                                .help("\(cell.date.formatted(style: .medium)) · \(cell.amount.formattedCurrency)")
                        }
                    }
                }
            } else {
                cellView(column.cells.first!)
                    .overlay(alignment: .bottom) {
                        Text(formatter.string(from: column.cells.first!.date))
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .offset(y: 12)
                    }
                    .padding(.bottom, 14)
            }
        }
    }
}

private func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
    return (0 ..< 7).map { offset in
        calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7]
    }
}
