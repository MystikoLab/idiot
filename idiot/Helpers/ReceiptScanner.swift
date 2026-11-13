import CoreGraphics
import Foundation
import PDFKit
import Vision

nonisolated enum ReceiptScanner {
    struct Result: Sendable, Equatable {
        var amount: Double?
        var title: String?
        var date: Date?

        var isEmpty: Bool {
            amount == nil && title == nil && date == nil
        }
    }

    static func scan(_ file: ReceiptFile) async -> Result {
        await Task.detached(priority: .userInitiated) {
            parse(lines: lines(in: file))
        }.value
    }

    static func parse(lines: [String], now: Date = .now) -> Result {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Result(amount: amount(in: cleaned), title: title(in: cleaned), date: date(in: cleaned, now: now))
    }

    private static func lines(in file: ReceiptFile) -> [String] {
        guard file.isPDF else {
            return recognize(VNImageRequestHandler(data: file.data, options: [:]))
        }
        let text = PDFDocument(data: file.data)?.page(at: 0)?.string ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 {
            return text.components(separatedBy: .newlines)
        }
        guard let image = AttachmentProcessor.renderFirstPage(ofPDF: file.data, maxPixelSize: 2400) else { return [] }
        return recognize(VNImageRequestHandler(cgImage: image, options: [:]))
    }

    private static func recognize(_ handler: VNImageRequestHandler) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard (try? handler.perform([request])) != nil else { return [] }

        let fragments = (request.results ?? []).compactMap { observation -> (text: String, box: CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        .sorted { $0.box.midY > $1.box.midY }

        var rows: [[(text: String, box: CGRect)]] = []
        for fragment in fragments {
            if let anchor = rows.last?.first, abs(anchor.box.midY - fragment.box.midY) < min(anchor.box.height, fragment.box.height) * 0.6 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    private static let amountPattern = #/(?:^|[^\d.,\/:\-])(\d{1,3}(?:[.,]\d{3})+|\d+)[.,](\d{2})(?![\d\/:\-])(?![.,]\d)/#

    private static func amounts(in line: String) -> [Double] {
        line.matches(of: amountPattern).compactMap { match in
            let whole = match.output.1.filter(\.isNumber)
            return Double("\(whole).\(match.output.2)")
        }
    }

    private static let strongTotalKeywords = ["grand total", "amount due", "balance due", "total due", "amount payable", "total payable"]
    private static let subtotalPattern = #/sub\s*-?\s*total/#
    private static let nonTotalPattern = #/total\s+(?:tax|vat|gst|savings?|discounts?|items?|qty|quantity)|(?:tax|vat|gst|items?)\s+total/#

    private static func totalRank(_ line: String) -> Int {
        let lowered = line.lowercased()
        guard lowered.firstMatch(of: subtotalPattern) == nil, lowered.firstMatch(of: nonTotalPattern) == nil else { return 0 }
        if strongTotalKeywords.contains(where: lowered.contains) {
            return 2
        }
        return lowered.contains("total") ? 1 : 0
    }

    private static func amount(in lines: [String]) -> Double? {
        var candidates: [(rank: Int, value: Double)] = []
        for (index, line) in lines.enumerated() {
            let rank = totalRank(line)
            guard rank > 0 else { continue }
            if let value = amounts(in: line).last {
                candidates.append((rank, value))
            } else if index + 1 < lines.count, totalRank(lines[index + 1]) == 0,
                      lines[index + 1].lowercased().firstMatch(of: subtotalPattern) == nil,
                      let value = amounts(in: lines[index + 1]).first
            {
                candidates.append((rank, value))
            }
        }
        if let best = candidates.map(\.rank).max() {
            return candidates.filter { $0.rank == best }.map(\.value).max()
        }
        return lines.flatMap(amounts(in:)).filter { $0 > 0 }.max()
    }

    private static let genericTitles = ["receipt", "invoice", "tax invoice", "welcome", "thank you", "thanks", "customer copy", "merchant copy", "order", "bill"]

    private static func title(in lines: [String]) -> String? {
        for line in lines.prefix(8) {
            let visible = line.filter { !$0.isWhitespace }
            let letters = visible.filter(\.isLetter)
            guard letters.count >= 3, letters.count * 2 > visible.count else { continue }
            guard amounts(in: line).isEmpty, candidateDates(in: line).isEmpty else { continue }
            let trimmed = line.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !genericTitles.contains(trimmed.lowercased()), !trimmed.contains("@"), !trimmed.lowercased().contains("www.") else { continue }
            let cased = trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
            return String(cased.prefix(60))
        }
        return nil
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let isoDatePattern = #/(?:^|\D)(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})(?!\d)/#
    private static let numericDatePattern = #/(?:^|\D)(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4}|\d{2})(?!\d)/#
    private static let dayMonthPattern = #/(?:^|\D)(\d{1,2})(?:st|nd|rd|th)?[\s\-.]*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s\-.,]*(\d{4}|\d{2})(?!\d)/#
    private static let monthDayPattern = #/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s.]*(\d{1,2})(?:st|nd|rd|th)?[\s,]+(\d{4})(?!\d)/#

    private static var dayComesFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: .current) ?? "dM"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return true }
        return day < month
    }

    private static func date(in lines: [String], now: Date) -> Date? {
        for line in lines {
            if let date = candidateDates(in: line).first(where: { isPlausible($0, now: now) }) {
                return date
            }
        }
        return nil
    }

    private static func candidateDates(in line: String) -> [Date] {
        let lowered = line.lowercased()
        var found: [Date?] = []
        if let match = lowered.firstMatch(of: isoDatePattern) {
            found.append(makeDate(year: match.output.1, month: Int(match.output.2), day: Int(match.output.3)))
        }
        if let match = lowered.firstMatch(of: dayMonthPattern) {
            found.append(makeDate(year: match.output.3, month: monthNumber(match.output.2), day: Int(match.output.1)))
        }
        if let match = lowered.firstMatch(of: monthDayPattern) {
            found.append(makeDate(year: match.output.3, month: monthNumber(match.output.1), day: Int(match.output.2)))
        }
        if let match = lowered.firstMatch(of: numericDatePattern), let first = Int(match.output.1), let second = Int(match.output.2) {
            let dayFirst = first > 12 || (second <= 12 && dayComesFirst)
            found.append(makeDate(year: match.output.3, month: dayFirst ? second : first, day: dayFirst ? first : second))
        }
        return found.compactMap { $0 }
    }

    private static func monthNumber(_ name: Substring) -> Int? {
        monthNames.firstIndex(of: String(name)).map { $0 + 1 }
    }

    private static func makeDate(year: Substring, month: Int?, day: Int?) -> Date? {
        guard var year = Int(year), let month, let day, (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        if year < 100 {
            year += 2000
        }
        let calendar = Calendar.current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func isPlausible(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        guard let oldest = calendar.date(byAdding: .year, value: -10, to: now) else { return false }
        let latest = calendar.startOfDay(for: now).addingTimeInterval(86400)
        return date >= oldest && date < latest
    }
}
