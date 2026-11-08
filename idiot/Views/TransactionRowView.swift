import SwiftUI

struct TransactionRowView: View {
    @Environment(\.amountsHidden) private var amountsHidden
    let transaction: Transaction
    let isOverLimit: Bool
    let lockPastMonths: Bool
    var isSelected: Bool = false

    private var category: Category? {
        transaction.category
    }

    private var isIncome: Bool {
        category?.type == .income
    }

    private var amountColor: Color {
        if transaction.isInvestment {
            return .investment
        }
        return isIncome ? .green : .primary
    }

    private var typeLabel: String {
        if transaction.isInvestment {
            return transaction.isInvestmentReturn ? "Investment return" : "Investment"
        }
        return isIncome ? "Income" : "Expense"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowContent
            if isOverLimit, let limit = category?.limit {
                overLimitPill(limit)
            }
        }
        .padding(.vertical, 6)
        .opacity(lockPastMonths && transaction.date.isInPastMonth ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .animation(.snappy(duration: 0.2), value: isSelected)
    }

    func rowBackground(isSelected: Bool) -> some View {
        let fill: Color = {
            if isSelected {
                return .accentColor.opacity(0.14)
            }
            #if os(macOS)
                return Color(nsColor: .controlBackgroundColor)
            #else
                return .clear
            #endif
        }()
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
            .padding(.horizontal, 4)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                if let category {
                    if transaction.isInvestment {
                        Text("\(category.name) · \(transaction.isInvestmentReturn ? "Return" : "Contribution")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(category.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(amountColor)
                    .contentTransition(.numericText())
                    .maskedAmount()

                Text(transaction.date.formatted(style: .medium))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overLimitPill(_ limit: Double) -> some View {
        Label("Over \(limit.formattedCurrency)", systemImage: "exclamationmark.triangle.fill")
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red.opacity(0.12), in: Capsule())
            .redacted(reason: amountsHidden ? .placeholder : [])
    }

    private var iconBadge: some View {
        Image(systemName: category?.iconName ?? "questionmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: category?.colorHex ?? "#8E8E93"))
            .frame(width: 30, height: 30)
            .background(Color(hex: category?.colorHex ?? "#8E8E93").opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var amountText: String {
        "\(transaction.signedCashAmount >= 0 ? "+" : "−")\(transaction.amount.formattedCurrency)"
    }

    private var accessibilityText: String {
        var parts = ["\(typeLabel): \(transaction.title)"]
        if !amountsHidden {
            parts.append(amountText)
        }
        if let category {
            parts.append("in \(category.name)")
        }
        parts.append(transaction.date.formatted(date: .long, time: .omitted))
        if isOverLimit {
            parts.append("category over limit")
        }
        return parts.joined(separator: ", ")
    }
}
