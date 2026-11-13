import Foundation

enum TransactionMatcher {
    struct TitleGroup: Identifiable {
        let id: String
        let latest: Transaction
        let count: Int
    }

    struct MonthStat: Identifiable {
        let month: Date
        let count: Int
        let total: Double

        var id: Date {
            month
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        var tokens = foldedTokens(title)[...]
        while tokens.count > 1, let last = tokens.last, isNumberish(last) {
            tokens = tokens.dropLast()
        }
        return tokens.joined(separator: " ")
    }

    static func titleGroups(_ txs: [Transaction]) -> [TitleGroup] {
        Dictionary(grouping: txs) { normalizedTitle($0.title) }
            .compactMap { key, items in
                guard !key.isEmpty, let latest = items.max(by: { $0.date < $1.date }) else { return nil }
                return TitleGroup(id: key, latest: latest, count: items.count)
            }
    }

    static func suggestions(for text: String, in groups: [TitleGroup], limit: Int = 5) -> [TitleGroup] {
        let typed = foldedTokens(text).joined(separator: " ")
        guard !typed.isEmpty else { return [] }
        let queries = Set([typed, normalizedTitle(text)])
        let ranked = groups.compactMap { group -> (group: TitleGroup, isPrefix: Bool)? in
            if queries.contains(where: { group.id.hasPrefix($0) }) {
                return (group, true)
            }
            if queries.contains(where: { group.id.contains($0) }) {
                return (group, false)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.isPrefix != rhs.isPrefix {
                return lhs.isPrefix
            }
            if lhs.group.count != rhs.group.count {
                return lhs.group.count > rhs.group.count
            }
            return lhs.group.latest.date > rhs.group.latest.date
        }
        return ranked.prefix(limit).map(\.group)
    }

    static func similar(to title: String, in txs: [Transaction]) -> [Transaction] {
        let key = normalizedTitle(title)
        return txs.filter { normalizedTitle($0.title) == key }
    }

    static func monthlyBreakdown(_ txs: [Transaction]) -> [MonthStat] {
        Dictionary(grouping: txs) { $0.date.startOfMonth }
            .map { month, items in
                MonthStat(month: month, count: items.count, total: items.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.month > $1.month }
    }

    static func monthSpan(_ txs: [Transaction]) -> Int {
        guard let first = txs.map(\.date).min(), let last = txs.map(\.date).max() else { return 1 }
        let diff = Calendar.current.dateComponents([.month], from: first.startOfMonth, to: last.startOfMonth).month ?? 0
        return max(1, diff + 1)
    }

    private static func foldedTokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func isNumberish(_ token: String) -> Bool {
        let digits = token.count(where: \.isNumber)
        return digits > 0 && digits >= token.count - digits
    }
}
