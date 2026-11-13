import Charts
import SwiftUI

struct GoalCardView: View {
    let progress: GoalEngine.Progress
    let series: [GoalEngine.SeriesPoint]

    private var projectedText: String {
        if progress.status == .reached {
            return "Reached"
        }
        guard let date = progress.projectedCompletion else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    private var requiredText: String {
        progress.requiredMonthly.map { "\($0.formattedCurrency)/mo" } ?? "—"
    }

    private var chartEnd: Date {
        max(series.last?.date ?? .now, progress.deadline ?? .distantPast)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                progressBlock
                stats
                chart
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            GoalIcon(iconName: progress.iconName, colorHex: progress.colorHex)

            VStack(alignment: .leading, spacing: 1) {
                Text(progress.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(progress.categoryName ?? "No category linked")
                    .font(.caption)
                    .foregroundStyle(progress.categoryName == nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            GoalStatusBadge(status: progress.status)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction)
                .tint(progress.tint)
                .accessibilityLabel("\(progress.name) progress")
                .accessibilityValue("\(progress.percent) percent")

            HStack {
                Text("\(progress.percent)%")
                    .monospacedDigit()
                Spacer()
                if let paceText = progress.paceText {
                    Text(paceText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .maskedAmount()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                stat("Saved", progress.saved.formattedCurrency)
                stat("Target", progress.target.formattedCurrency)
                stat("Remaining", progress.remaining.formattedCurrency)
            }
            GridRow {
                stat("Needed monthly", requiredText)
                stat("Projected", projectedText)
                stat("Since", progress.startDate.formatted(.dateTime.day().month(.abbreviated).year()))
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .maskedAmount()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart {
            ForEach(series) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Saved", point.saved),
                    series: .value("Line", "Saved")
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color(hex: progress.colorHex))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let deadline = progress.deadline, deadline > progress.startDate {
                LineMark(
                    x: .value("Date", progress.startDate),
                    y: .value("Saved", 0),
                    series: .value("Line", "Pace")
                )
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(
                    x: .value("Date", deadline),
                    y: .value("Saved", progress.target),
                    series: .value("Line", "Pace")
                )
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            RuleMark(y: .value("Target", progress.target))
                .foregroundStyle(.green.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .bottom, alignment: .trailing) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: Calendar.current.startOfDay(for: progress.startDate) ... max(chartEnd, progress.startDate.addingTimeInterval(86400)))
        .chartLegend(.hidden)
        .frame(height: 150)
        .accessibilityLabel("\(progress.name) progress over time")
        .accessibilityValue(progress.amountText)
    }
}
