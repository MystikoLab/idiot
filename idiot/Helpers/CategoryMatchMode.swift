import Foundation

enum CategoryMatchMode: String, CaseIterable, Identifiable {
    case main
    case sub
    case either

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .main: "Main category only"
        case .sub: "Sub category only"
        case .either: "Either"
        }
    }

    func categories(of transaction: Transaction) -> [Category] {
        switch self {
        case .main: [transaction.category].compactMap(\.self)
        case .sub: [transaction.subCategory].compactMap(\.self)
        case .either: [transaction.category, transaction.subCategory].compactMap(\.self)
        }
    }

    func matches(_ transaction: Transaction, where predicate: (Category) -> Bool) -> Bool {
        categories(of: transaction).contains(where: predicate)
    }
}
