import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum CSVExporter {
    static func csv(for transactions: [Transaction]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["Date,Title,Description,Category,Sub Category,Type,Amount"]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            lines.append([
                formatter.string(from: transaction.date),
                transaction.title,
                transaction.desc ?? "",
                transaction.category?.name ?? "",
                transaction.subCategory?.name ?? "",
                typeLabel(for: transaction),
                String(format: "%.2f", transaction.signedCashAmount),
            ].map { escape($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func typeLabel(for transaction: Transaction) -> String {
        switch transaction.category?.type {
        case .income:
            "Income"
        case .investment:
            transaction.isInvestmentReturn ? "Investment Return" : "Investment"
        default:
            "Expense"
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

nonisolated struct CSVFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(file.filename).csv")
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
