import Charts
import SwiftUI

struct RecurringSplitSection: View {
    let committed: Double
    let discretionary: Double
    let ruleSpend: [AnalyticsEngine.RuleSpend]

    @State private var showHelp = false

    var body: some View {
        let total = committed + discretionary
        if total <= 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recurring vs Discretionary")
                        .font(.headline)
                        .textSelection(.enabled)
                    Spacer()
                    helpButton
                }

                GroupBox {
                    #if os(macOS)
                        HStack(alignment: .center, spacing: 20) {
                            donut(total: total)
                                .frame(width: 140, height: 140)

                            legend(total: total)

                            if !ruleSpend.isEmpty {
                                Divider()
                                topRules
                            }
                        }
                        .padding(.vertical, 4)
                    #else
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 20) {
                                donut(total: total)
                                    .frame(width: 130, height: 130)

                                VStack(alignment: .leading, spacing: 8) {
                                    legendRow(label: "Committed", amount: committed, total: total, color: Color(hex: "#5AC8FA"))
                                    legendRow(label: "Discretionary", amount: discretionary, total: total, color: .gray.opacity(0.55))
                                }
                            }

                            if !ruleSpend.isEmpty {
                                Divider()
                                topRules
                            }
                        }
                        .padding(.vertical, 4)
                    #endif
                }
            }
            #if os(macOS)
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                helpContent
            }
            #else
            .sheet(isPresented: $showHelp) {
                helpContent
                    .presentationDetents([.medium])
            }
            #endif
        }
    }

    private var helpButton: some View {
        Button {
            showHelp = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help")
        .help("What does this chart show?")
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recurring vs Discretionary")
                .font(.title3.weight(.semibold))

            Text("This donut splits your expenses in the selected range into two buckets based on how predictable they are.")
                .font(.callout)

            legendHelpRow(color: Color(hex: "#5AC8FA"), title: "Committed", detail: "Spending tied to a recurring rule (subscriptions, rent, memberships). The slices are normalized to a monthly cost, so irregular frequencies are weighted evenly.")

            legendHelpRow(color: .gray.opacity(0.55), title: "Discretionary", detail: "One-off, regular spending that is not part of any recurring rule.")

            dividerHelpRow(title: "Top recurring", detail: "Lists the recurring rules that cost the most in the range, how many transactions they produced, and their total spend.")

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: 420, alignment: .leading)
        .frame(minHeight: 260)
    }

    private func legendHelpRow(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func dividerHelpRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Divider()
                .frame(width: 10, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func legend(total: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(label: "Committed", amount: committed, total: total, color: Color(hex: "#5AC8FA"))
            legendRow(label: "Discretionary", amount: discretionary, total: total, color: .gray.opacity(0.55))
        }
    }

    private func donut(total: Double) -> some View {
        let data: [(String, Double, Color)] = [
            ("Committed", committed, Color(hex: "#5AC8FA")),
            ("Discretionary", discretionary, Color.gray.opacity(0.55)),
        ]
        return Chart(data, id: \.0) { item in
            SectorMark(
                angle: .value("Total", max(item.1, 0.0001)),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(item.2)
            .annotation(position: .overlay) {
                Text("\(String(format: "%.0f", item.1 / total * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(item.0)
            .accessibilityValue(item.1.formattedCurrency)
        }
        .help("Committed \(committed.formattedCurrency) · Discretionary \(discretionary.formattedCurrency)")
    }

    private var topRules: some View {
        let visible = Array(ruleSpend.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Top recurring")
                .font(.callout.weight(.semibold))

            ForEach(visible) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: rule.colorHex))
                            .frame(width: 8, height: 8)
                        Text(rule.title)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer()
                        Text(rule.total.formattedCurrency)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                    }
                    Text("\(rule.count) transactions in range")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if ruleSpend.count > visible.count {
                Text("+ \(ruleSpend.count - visible.count) other rule(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func legendRow(label: String, amount: Double, total: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(amount.formattedCurrency)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .textSelection(.enabled)
                Text("\(String(format: "%.0f", amount / total * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
