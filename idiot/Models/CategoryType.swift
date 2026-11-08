import Foundation

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case investment

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .income:
            "Income"
        case .expense:
            "Expense"
        case .investment:
            "Investment"
        }
    }

    var sortRank: Int {
        switch self {
        case .expense:
            0
        case .investment:
            1
        case .income:
            2
        }
    }
}
