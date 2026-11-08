import Charts
import SwiftUI

struct InvestmentsSection: View {
    let flows: [AnalyticsEngine.InvestmentFlow]
    let holdings: [AnalyticsEngine.HoldingStat]
    let investedSeries: [AnalyticsEngine.InvestedPoint]
    let granularity: Granularity

    @State private var selectedPeriod: String?

    private var contributed: Double {
        holdings.reduce(0) { $0 + $1.contributed }
    }

    private var returned: Double {
        holdings.reduce(0) { $0 + $1.returned }
    }

    private var netInvested: Double {
        contributed - returned
    }

    private var allTimeInvested: Double {
        investedSeries.last?.netInvested ?? 0
    }

    private var hasAllTimeActivity: Bool {
        investedSeries.contains { $0.netInvested != 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investments")
                .font(.headline)

            if holdings.isEmpty, !hasAllTimeActivity {
                ContentUnavailableView(
                    "No investments yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Add a transaction to an investment category to see contributions, returns and holdings here.")
                )
            } else {
                statTiles

                #if os(macOS)
                    HStack(alignment: .top, spacing: 12) {
                        flowChart
                        investedChart
                    }
                #else
                    flowChart
                    investedChart
                #endif

                holdingsList
            }
        }
    }

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
            statTile("Contributed", value: contributed.formattedCurrency, color: .investment)
            statTile("Returned", value: returned.formattedCurrency, color: .green)
            statTile("Net invested", value: netInvested.formattedCurrency, color: .investment)
            statTile("Return ratio", value: returnRatioText, color: .primary)
                .help("Returns as a share of contributions in this range")
            statTile("All-time invested", value: allTimeInvested.formattedCurrency, color: .investment)
                .help("Contributions minus returns across all time, up to the end of this range")
        }
    }

    private var returnRatioText: String {
        guard contributed > 0 else { return "—" }
        return String(format: "%.0f%%", returned / contributed * 100)
    }

    private func statTile(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var flowChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contributions vs returns")
                    .font(.subheadline.weight(.semibold))

                if flows.isEmpty {
                    emptyChartText("No investment activity in this range.")
                } else {
                    Chart {
                        ForEach(flows) { flow in
                            let label = flow.bucket.periodLabel(for: granularity)
                            BarMark(
                                x: .value("Period", label),
                                y: .value("Amount", flow.contributions)
                            )
                            .foregroundStyle(by: .value("Flow", "Contributions"))
                            .position(by: .value("Flow", "Contributions"))
                            .cornerRadius(3)
                            .accessibilityLabel("Contributions, \(label)")
                            .accessibilityValue(flow.contributions.formattedCurrency)

                            BarMark(
                                x: .value("Period", label),
                                y: .value("Amount", flow.returns)
                            )
                            .foregroundStyle(by: .value("Flow", "Returns"))
                            .position(by: .value("Flow", "Returns"))
                            .cornerRadius(3)
                            .accessibilityLabel("Returns, \(label)")
                            .accessibilityValue(flow.returns.formattedCurrency)
                        }

                        if let selectedPeriod {
                            RuleMark(x: .value("Period", selectedPeriod))
                                .foregroundStyle(.secondary.opacity(0.25))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    periodAnnotation(selectedPeriod)
                                }
                        }
                    }
                    .chartForegroundStyleScale(["Contributions": Color.investment, "Returns": Color.green])
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount.formattedCurrency)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedPeriod)
                    .frame(height: 220)
                }
            }
        }
    }

    @ViewBuilder
    private func periodAnnotation(_ label: String) -> some View {
        if let flow = flows.first(where: { $0.bucket.periodLabel(for: granularity) == label }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                Text("Contributed \(flow.contributions.formattedCurrency)")
                    .foregroundStyle(Color.investment)
                Text("Returned \(flow.returns.formattedCurrency)")
                    .foregroundStyle(.green)
            }
            .font(.caption2.monospacedDigit())
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var investedChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Net invested over time")
                    .font(.subheadline.weight(.semibold))

                if investedSeries.count < 2 {
                    emptyChartText("Not enough data to plot.")
                } else {
                    Chart(investedSeries) { point in
                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Net invested", point.netInvested)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.investment.opacity(0.3), Color.investment.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Net invested", point.netInvested)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Color.investment)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(point.netInvested.formattedCurrency)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount.formattedCurrency)
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func emptyChartText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
    }

    private var holdingsList: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Holdings")
                    .font(.subheadline.weight(.semibold))

                if holdings.isEmpty {
                    Text("No investment transactions in this range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(holdings) { holding in
                        holdingRow(holding)
                        if holding.id != holdings.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func holdingRow(_ holding: AnalyticsEngine.HoldingStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: holding.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: holding.colorHex))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: holding.colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .fontWeight(.medium)
                    Text(holdingCaption(holding))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(holding.netInvested.formattedCurrency)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.investment)
                    Text("net invested")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let ratio = holding.returnRatio {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: min(ratio, 100) / 100)
                        .tint(ratio >= 100 ? Color.green : Color.investment)
                    Text("\(holding.returned.formattedCurrency) returned of \(holding.contributed.formattedCurrency) contributed (\(Int(ratio))%)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func holdingCaption(_ holding: AnalyticsEngine.HoldingStat) -> String {
        var parts = ["\(holding.transactionCount) transaction\(holding.transactionCount == 1 ? "" : "s")"]
        if let last = holding.lastActivity {
            parts.append("last \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}
