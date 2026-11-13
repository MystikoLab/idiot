import SwiftUI

struct TransactionSuggestionList: View {
    let suggestions: [TransactionMatcher.TitleGroup]
    let onPick: (Transaction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion.latest)
                } label: {
                    row(suggestion.latest, count: suggestion.count)
                }
                .buttonStyle(.plain)

                if suggestion.id != suggestions.last?.id {
                    Divider()
                }
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func row(_ transaction: Transaction, count: Int) -> some View {
        let colorHex = transaction.category?.colorHex ?? "#8E8E93"
        return HStack(spacing: 8) {
            Image(systemName: transaction.category?.iconName ?? "questionmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(hex: colorHex))
                .frame(width: 22, height: 22)
                .background(Color(hex: colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.title)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(transaction.category?.name ?? "Uncategorized") · used \(count)×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(transaction.signedCashAmount >= 0 ? "+" : "−")\(transaction.amount.formattedCurrency)")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(amountColor(transaction))
                .maskedAmount()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func amountColor(_ transaction: Transaction) -> Color {
        if transaction.isInvestment {
            return .investment
        }
        return transaction.category?.type == .income ? .green : .primary
    }
}
