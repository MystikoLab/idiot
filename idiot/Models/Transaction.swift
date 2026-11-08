import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var title: String = ""
    var desc: String?
    var amount: Double = 0
    var date: Date = Date()
    var category: Category?
    var createdAt: Date = Date()
    var syncStamp: Date = Date()
    var recurringRuleID: UUID?
    var isInvestmentReturn: Bool = false

    init(
        id: UUID = UUID(),
        title: String = "",
        desc: String? = nil,
        amount: Double = 0,
        date: Date = .now,
        category: Category? = nil,
        createdAt: Date = .now,
        recurringRuleID: UUID? = nil,
        isInvestmentReturn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.desc = desc
        self.amount = amount
        self.date = date
        self.category = category
        self.createdAt = createdAt
        self.recurringRuleID = recurringRuleID
        self.isInvestmentReturn = isInvestmentReturn
    }
}

extension Transaction {
    var isInvestment: Bool {
        category?.type == .investment
    }

    var signedCashAmount: Double {
        switch category?.type {
        case .income:
            amount
        case .investment:
            isInvestmentReturn ? amount : -amount
        default:
            -amount
        }
    }

    var investedAmount: Double {
        guard isInvestment else { return 0 }
        return isInvestmentReturn ? -amount : amount
    }
}

extension [Transaction] {
    var netInvested: Double {
        reduce(0) { $0 + $1.investedAmount }
    }

    var investmentContributions: Double {
        filter { $0.isInvestment && !$0.isInvestmentReturn }.reduce(0) { $0 + $1.amount }
    }

    var investmentReturns: Double {
        filter { $0.isInvestment && $0.isInvestmentReturn }.reduce(0) { $0 + $1.amount }
    }
}
