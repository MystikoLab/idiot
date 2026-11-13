import Foundation

enum CSVImporter {
    struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let description: String
        let amount: Double
        let sourceCategory: String?
    }

    enum ImportError: LocalizedError {
        case unreadable
        case noTransactions

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "The file could not be read as text."
            case .noTransactions:
                "No transactions were found. The file needs a header row with a date column and either an amount column or debit and credit columns."
            }
        }
    }

    private struct Columns {
        var date: Int
        var description: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
        var category: Int?
        var state: Int?
    }

    static func load(url: URL) throws -> [Row] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        let rows = parse(text)
        guard !rows.isEmpty else { throw ImportError.noTransactions }
        return rows
    }

    static func parse(_ text: String) -> [Row] {
        var result: [Row] = []
        var columns: Columns?

        for fields in records(in: text) {
            if let header = detectColumns(fields) {
                columns = header
                continue
            }
            guard let current = columns else { continue }
            switch makeRow(fields, columns: current) {
            case let .row(row):
                result.append(row)
            case .skip:
                continue
            case .endOfSection:
                columns = nil
            }
        }
        return result
    }

    private enum Outcome {
        case row(Row)
        case skip
        case endOfSection
    }

    private static func makeRow(_ fields: [String], columns: Columns) -> Outcome {
        guard let date = parseDate(field(fields, columns.date)) else { return .endOfSection }

        if let state = field(fields, columns.state)?.lowercased(),
           ["reverted", "declined", "failed", "cancelled", "canceled"].contains(state)
        {
            return .skip
        }

        let amount: Double
        if let index = columns.amount, let value = parseAmount(field(fields, index)) {
            amount = value
        } else {
            let credit = parseAmount(field(fields, columns.credit)).map(abs) ?? 0
            let debit = parseAmount(field(fields, columns.debit)).map(abs) ?? 0
            amount = credit - debit
        }
        guard amount != 0 else { return .skip }

        let description = field(fields, columns.description) ?? ""
        return .row(Row(
            date: date,
            description: description.isEmpty ? "Imported transaction" : description,
            amount: amount,
            sourceCategory: field(fields, columns.category)
        ))
    }

    private static func field(_ fields: [String], _ index: Int?) -> String? {
        guard let index, fields.indices.contains(index) else { return nil }
        let value = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func detectColumns(_ fields: [String]) -> Columns? {
        let names = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        func first(_ matches: (String) -> Bool, excluding used: [Int?] = []) -> Int? {
            names.indices.first { matches(names[$0]) && !used.contains($0) }
        }

        guard let date = first({ $0 == "date" }) ?? first({ $0.contains("date") }) else { return nil }

        let amount = first { name in
            name == "amount" || name.hasPrefix("amount ") || name.hasPrefix("amount(") ||
                name == "money in/out" || name == "value" || name == "transaction amount"
        }
        let debit = first({ ["debit", "debit amount", "money out", "paid out", "withdrawal", "withdrawals", "out"].contains($0) }, excluding: [amount])
        let credit = first({ ["credit", "credit amount", "money in", "paid in", "deposit", "deposits", "in"].contains($0) }, excluding: [amount])
        guard amount != nil || debit != nil || credit != nil else { return nil }

        let description = first { ["description", "details", "narrative", "payee", "merchant", "name", "memo", "title", "reference"].contains($0) }
            ?? first { $0.contains("description") }

        return Columns(
            date: date,
            description: description,
            amount: amount,
            debit: debit,
            credit: credit,
            category: first { $0 == "category" } ?? first { $0 == "type" },
            state: first { $0 == "state" || $0 == "status" }
        )
    }

    static func parseAmount(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let isNegative = raw.contains("-") || raw.contains("−") || (raw.contains("(") && raw.contains(")"))
        var digits = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !digits.isEmpty else { return nil }

        if let lastComma = digits.lastIndex(of: ","), digits.distance(from: lastComma, to: digits.endIndex) == 3,
           !digits.contains(".")
        {
            digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let lastComma = digits.lastIndex(of: ","), let lastDot = digits.lastIndex(of: "."), lastComma > lastDot {
            digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            digits = digits.replacingOccurrences(of: ",", with: "")
        }

        guard let value = Double(digits) else { return nil }
        return isNegative ? -value : value
    }

    private static let dateFormatters: [DateFormatter] = [
        "MMM d, yyyy", "MMM d yyyy", "d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "MMMM d, yyyy",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy/MM/dd", "dd-MMM-yyyy",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    static func records(in text: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?

        func endRecord() {
            fields.append(current)
            current = ""
            if fields.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                records.append(fields)
            }
            fields = []
        }

        while let scalar = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if scalar == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.unicodeScalars.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.unicodeScalars.append(scalar)
                }
                continue
            }

            switch scalar {
            case "\"":
                inQuotes = true
            case ",":
                fields.append(current)
                current = ""
            case "\r":
                if let next = iterator.next(), next != "\n" {
                    pending = next
                }
                endRecord()
            case "\n":
                endRecord()
            case "\u{FEFF}":
                break
            default:
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty || !fields.isEmpty {
            endRecord()
        }
        return records
    }
}
