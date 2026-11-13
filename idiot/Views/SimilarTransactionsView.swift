import SwiftData
import SwiftUI

struct SimilarTitle: Identifiable, Hashable {
    let title: String

    var id: String {
        title
    }
}

struct SimilarTransactionsView: View {
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    var body: some View {
        let matches = TransactionMatcher.similar(to: title, in: allTransactions)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if matches.isEmpty {
                        ContentUnavailableView(
                            "No similar transactions",
                            systemImage: "square.on.square.dashed",
                            description: Text("Nothing else is named like “\(title)”.")
                        )
                    } else {
                        statTiles(matches)
                        monthlySection(TransactionMatcher.monthlyBreakdown(matches))
                        transactionsSection(matches)
                    }
                }
                .padding()
            }
            .navigationTitle(title.isEmpty ? "Untitled" : title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func statTiles(_ matches: [Transaction]) -> some View {
        let total = matches.reduce(0) { $0 + $1.amount }
        let months = TransactionMatcher.monthSpan(matches)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            statTile("Transactions", value: "\(matches.count)", masked: false)
            statTile("Total", value: total.formattedCurrency)
            statTile("Average", value: matches.map(\.amount).averageOrZero.formattedCurrency)
            statTile("Per month", value: (total / Double(months)).formattedCurrency)
                .help("Total divided by the \(months) month(s) these transactions span")
        }
    }

    private func statTile(_ label: String, value: String, masked: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if masked {
                tileValue(value)
                    .maskedAmount()
            } else {
                tileValue(value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tileValue(_ value: String) -> some View {
        Text(value)
            .font(.title3.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func monthlySection(_ months: [TransactionMatcher.MonthStat]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("By month")
                    .font(.subheadline.weight(.semibold))

                ForEach(months) { stat in
                    HStack {
                        Text(stat.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text("\(stat.count)×")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(stat.total.formattedCurrency)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(minWidth: 90, alignment: .trailing)
                            .maskedAmount()
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transactionsSection(_ matches: [Transaction]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transactions")
                    .font(.subheadline.weight(.semibold))

                ForEach(matches) { transaction in
                    transactionRow(transaction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let colorHex = transaction.category?.colorHex ?? "#8E8E93"
        return HStack(spacing: 8) {
            Image(systemName: transaction.category?.iconName ?? "questionmark.circle")
                .frame(width: 16)
                .foregroundStyle(Color(hex: colorHex))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.date.formatted(style: .medium))
                Text(transaction.category?.name ?? "Uncategorized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(transaction.signedCashAmount >= 0 ? "+" : "−")\(transaction.amount.formattedCurrency)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(amountColor(transaction))
                .maskedAmount()
        }
        .font(.callout)
    }

    private func amountColor(_ transaction: Transaction) -> Color {
        if transaction.isInvestment {
            return .investment
        }
        return transaction.category?.type == .income ? .green : .primary
    }
}
