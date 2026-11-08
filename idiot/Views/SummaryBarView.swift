import SwiftData
import SwiftUI

struct SummaryBarView: View {
    let selectedMonth: Date

    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]

    private var transactions: [Transaction] {
        let start = selectedMonth.startOfMonth
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? selectedMonth.endOfMonth
        return allTransactions.filter { $0.date >= start && $0.date < end }
    }

    private var totalIncome: Double {
        transactions
            .filter { $0.category?.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalExpense: Double {
        transactions
            .filter { $0.category?.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    private var netTotal: Double {
        totalIncome - totalExpense
    }

    private var broughtForwardBalance: Double {
        let start = selectedMonth.startOfMonth
        let txTotal = allTransactions
            .filter { $0.date < start }
            .reduce(0) { $0 + $1.signedCashAmount }
        return txTotal + OpeningBalance.amount
    }

    private var totalBalance: Double {
        broughtForwardBalance + transactions.reduce(0) { $0 + $1.signedCashAmount }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 18) {
                Text("+\(totalIncome.formattedCurrency)")
                    .foregroundStyle(.green)

                Text("−\(totalExpense.formattedCurrency)")
                    .foregroundStyle(.red)

                Text("= \(netPrefix)\(abs(netTotal).formattedCurrency)")
                    .fontWeight(.bold)
                    .foregroundStyle(netColor)
            }
            .font(.callout.monospacedDigit())

            HStack(spacing: 18) {
                Text("Brought forward: \(broughtForwardBalance.formattedCurrency)")
                    .foregroundStyle(.secondary)

                Text("Balance: \(balancePrefix)\(abs(totalBalance).formattedCurrency)")
                    .fontWeight(.semibold)
                    .foregroundStyle(balanceColor)
            }
            .font(.caption.monospacedDigit())
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var netPrefix: String {
        if netTotal > 0 {
            return "+"
        }

        if netTotal < 0 {
            return "−"
        }

        return ""
    }

    private var netColor: Color {
        if netTotal > 0 {
            return .green
        }

        if netTotal < 0 {
            return .red
        }

        return .primary
    }

    private var balancePrefix: String {
        if totalBalance > 0 {
            return "+"
        }

        if totalBalance < 0 {
            return "−"
        }

        return ""
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
}
