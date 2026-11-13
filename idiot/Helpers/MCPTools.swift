#if os(macOS)
    import Foundation
    import SwiftData

    struct MCPToolError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }

    @MainActor
    enum MCPTools {
        static let writeToolNames: Set<String> = ["add_transaction", "update_transaction", "delete_transaction"]

        private static let maxTitleLength = 200
        private static let maxDescriptionLength = 2000
        private static let maxAmount = 1_000_000_000_000.0

        static func definitions(includeWrites: Bool) -> [[String: Any]] {
            allDefinitions.filter { includeWrites || !writeToolNames.contains($0["name"] as? String ?? "") }
        }

        static func call(name: String, arguments: [String: Any], context: ModelContext, writesEnabled: Bool) throws -> Any {
            guard let definition = allDefinitions.first(where: { $0["name"] as? String == name }) else {
                throw MCPToolError("Unknown tool: \(name)")
            }
            if writeToolNames.contains(name), !writesEnabled {
                throw MCPToolError("Write access is turned off. Enable it in Idiot > Settings > Agent Access.")
            }
            let schema = definition["inputSchema"] as? [String: Any]
            let allowed = Set((schema?["properties"] as? [String: Any] ?? [:]).keys)
            if let unknown = arguments.keys.first(where: { !allowed.contains($0) }) {
                throw MCPToolError("Unknown argument: \(unknown)")
            }

            switch name {
            case "get_month_summary": return try monthSummary(arguments, context: context)
            case "list_transactions": return try listTransactions(arguments, context: context)
            case "list_categories": return try listCategories(context: context)
            case "list_recurring_rules": return try listRecurringRules(context: context)
            case "get_spending_trend": return try spendingTrend(arguments, context: context)
            case "get_forecast": return try forecast(context: context)
            case "add_transaction": return try addTransaction(arguments, context: context)
            case "update_transaction": return try updateTransaction(arguments, context: context)
            case "delete_transaction": return try deleteTransaction(arguments, context: context)
            default: throw MCPToolError("Unknown tool: \(name)")
            }
        }

        // MARK: Definitions

        private static let allDefinitions: [[String: Any]] = [
            tool(
                "get_month_summary",
                "Income, expenses, net, closing balance and per-category budget status for one month.",
                properties: ["month": monthProperty("Month as yyyy-MM. Defaults to the current month.")],
                readOnly: true
            ),
            tool(
                "list_transactions",
                "Search transactions, newest first. Returns matching totals along with one page of results. Each transaction has a main category and an optional sub_category, which is a label only: amounts and types always belong to the main category.",
                properties: [
                    "from": dateProperty("Earliest date, inclusive, as yyyy-MM-dd."),
                    "to": dateProperty("Latest date, inclusive, as yyyy-MM-dd."),
                    "category": ["type": "string", "description": "Category name or id."],
                    "category_match": [
                        "type": "string",
                        "enum": ["main", "sub", "either"],
                        "description": "Which category the category filter checks: main, sub or either. Defaults to main.",
                    ],
                    "type": ["type": "string", "enum": ["income", "expense", "investment"]],
                    "search": ["type": "string", "description": "Case-insensitive text to find in the title or description."],
                    "min_amount": ["type": "number"],
                    "max_amount": ["type": "number"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "Defaults to 100."],
                    "offset": ["type": "integer", "minimum": 0, "description": "Defaults to 0."],
                ],
                readOnly: true
            ),
            tool("list_categories", "All categories with their type and monthly limit.", properties: [:], readOnly: true),
            tool(
                "list_recurring_rules",
                "Subscriptions and other recurring rules, with next due date and normalized monthly cost.",
                properties: [:],
                readOnly: true
            ),
            tool(
                "get_spending_trend",
                "Income, expenses, net and per-category spend for each of the most recent months.",
                properties: ["months": ["type": "integer", "minimum": 1, "maximum": 60, "description": "Defaults to 6."]],
                readOnly: true
            ),
            tool("get_forecast", "End-of-month projection for the current month, including upcoming recurring items.", properties: [:], readOnly: true),
            tool(
                "add_transaction",
                "Add a transaction. Income, expense or investment comes from the category. sub_category is an optional second label. Dates before the current month are rejected.",
                properties: [
                    "title": ["type": "string"],
                    "amount": ["type": "number", "exclusiveMinimum": 0, "description": "Always positive."],
                    "category": ["type": "string", "description": "Category name or id."],
                    "sub_category": ["type": "string", "description": "Optional sub category name or id. Must differ from category."],
                    "date": dateProperty("Date as yyyy-MM-dd. Defaults to today."),
                    "description": ["type": "string"],
                    "investment_return": investmentReturnProperty,
                ],
                required: ["title", "amount", "category"],
                readOnly: false
            ),
            tool(
                "update_transaction",
                "Change fields on a current-month transaction. Transactions in past months are locked.",
                properties: [
                    "id": ["type": "string"],
                    "title": ["type": "string"],
                    "amount": ["type": "number", "exclusiveMinimum": 0],
                    "category": ["type": "string", "description": "Category name or id."],
                    "sub_category": ["type": "string", "description": "Sub category name or id. An empty string clears it."],
                    "date": dateProperty("Date as yyyy-MM-dd."),
                    "description": ["type": "string", "description": "An empty string clears the description."],
                    "investment_return": investmentReturnProperty,
                ],
                required: ["id"],
                readOnly: false
            ),
            tool(
                "delete_transaction",
                "Permanently delete a current-month transaction. Transactions in past months are locked.",
                properties: ["id": ["type": "string"]],
                required: ["id"],
                readOnly: false,
                destructive: true
            ),
        ]

        private static func tool(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String] = [],
            readOnly: Bool,
            destructive: Bool = false
        ) -> [String: Any] {
            [
                "name": name,
                "description": description,
                "inputSchema": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                    "additionalProperties": false,
                ] as [String: Any],
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "openWorldHint": false],
            ]
        }

        private static let investmentReturnProperty: [String: Any] = [
            "type": "boolean",
            "description": "Investment categories only: true for money coming back (sale, dividend), false for a contribution. Defaults to false.",
        ]

        private static func dateProperty(_ description: String) -> [String: Any] {
            ["type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": description]
        }

        private static func monthProperty(_ description: String) -> [String: Any] {
            ["type": "string", "pattern": "^\\d{4}-\\d{2}$", "description": description]
        }

        // MARK: Read tools

        private static func monthSummary(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            let month = try monthArgument("month", in: arguments) ?? Date.now.startOfMonth
            let range = monthRange(month)
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let monthTxs = all.filter { range.contains($0.date) }
            let categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))

            let rows: [[String: Any]] = categories.compactMap { category in
                let total = monthTxs.filter { $0.category?.id == category.id }.reduce(0) { $0 + $1.amount }
                guard total > 0 || category.limit != nil else { return nil }
                return [
                    "category": category.name,
                    "type": category.type.rawValue,
                    "total": money(total),
                    "limit": nullable(category.limit.map(money)),
                    "remaining": nullable(category.limit.map { money($0 - total) }),
                    "over_limit": category.limit.map { total > $0 } ?? false,
                ]
            }

            return [
                "month": monthFormatter.string(from: month),
                "income": money(AnalyticsEngine.incomeTotal(monthTxs)),
                "expense": money(AnalyticsEngine.expenseTotal(monthTxs)),
                "net": money(AnalyticsEngine.netTotal(monthTxs)),
                "invested": money(monthTxs.netInvested),
                "closing_balance": money(balance(of: all.filter { $0.date < range.upperBound })),
                "transaction_count": monthTxs.count,
                "categories": rows,
            ]
        }

        private static func listTransactions(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            let from = try dateArgument("from", in: arguments)
            let to = try dateArgument("to", in: arguments).flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
            let categories = try context.fetch(FetchDescriptor<Category>())
            let category = try stringArgument("category", in: arguments).map { try resolveCategory($0, in: categories) }
            let matchValue = try stringArgument("category_match", in: arguments)
            guard let matchMode = CategoryMatchMode(rawValue: matchValue ?? "main") else {
                throw MCPToolError("category_match must be main, sub or either")
            }
            let type = try stringArgument("type", in: arguments)
            if let type, CategoryType(rawValue: type) == nil {
                throw MCPToolError("type must be income, expense or investment")
            }
            let search = try stringArgument("search", in: arguments)
            let minAmount = try numberArgument("min_amount", in: arguments)
            let maxAmount = try numberArgument("max_amount", in: arguments)
            let limit = try integerArgument("limit", in: arguments, range: 1 ... 500) ?? 100
            let offset = try integerArgument("offset", in: arguments, range: 0 ... Int.max) ?? 0

            let descriptor = FetchDescriptor<Transaction>(sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ])
            let matches = try context.fetch(descriptor).filter { tx in
                if let from, tx.date < from {
                    return false
                }
                if let to, tx.date >= to {
                    return false
                }
                if let category, !matchMode.matches(tx, where: { $0.id == category.id }) {
                    return false
                }
                if let type, tx.category?.type.rawValue != type {
                    return false
                }
                if let minAmount, tx.amount < minAmount {
                    return false
                }
                if let maxAmount, tx.amount > maxAmount {
                    return false
                }
                if let search, !search.isEmpty {
                    let inTitle = tx.title.localizedCaseInsensitiveContains(search)
                    let inDescription = tx.desc?.localizedCaseInsensitiveContains(search) ?? false
                    if !inTitle, !inDescription {
                        return false
                    }
                }
                return true
            }

            return [
                "total_count": matches.count,
                "total_income": money(AnalyticsEngine.incomeTotal(matches)),
                "total_expense": money(AnalyticsEngine.expenseTotal(matches)),
                "offset": offset,
                "transactions": matches.dropFirst(offset).prefix(limit).map(serialize),
            ]
        }

        private static func listCategories(context: ModelContext) throws -> Any {
            let categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))
            return [
                "categories": categories.map { category -> [String: Any] in
                    [
                        "id": category.id.uuidString,
                        "name": category.name,
                        "type": category.type.rawValue,
                        "monthly_limit": nullable(category.limit.map(money)),
                    ]
                },
            ]
        }

        private static func listRecurringRules(context: ModelContext) throws -> Any {
            let rules = try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [SortDescriptor(\.title)]))
            return [
                "rules": rules.map { rule -> [String: Any] in
                    [
                        "id": rule.id.uuidString,
                        "title": rule.title,
                        "amount": money(rule.amount),
                        "frequency": rule.frequency.rawValue,
                        "category": nullable(rule.category?.name),
                        "type": nullable(rule.category?.type.rawValue),
                        "active": rule.isActive,
                        "next_due": nullable(RecurringEngine.nextDueDate(for: rule).map(dateFormatter.string(from:))),
                        "end_date": nullable(rule.endDate.map(dateFormatter.string(from:))),
                        "monthly_cost": money(rule.monthlyNormalizedCost),
                    ]
                },
            ]
        }

        private static func spendingTrend(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            let count = try integerArgument("months", in: arguments, range: 1 ... 60) ?? 6
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let current = Date.now.startOfMonth

            let rows: [[String: Any]] = (0 ..< count).reversed().compactMap { offset in
                guard let month = Calendar.current.date(byAdding: .month, value: -offset, to: current) else { return nil }
                let range = monthRange(month)
                let txs = all.filter { range.contains($0.date) }
                let byCategory = Dictionary(grouping: txs.filter { $0.category?.type == .expense }) { $0.category?.name ?? "Uncategorized" }
                    .mapValues { money($0.reduce(0) { $0 + $1.amount }) }
                return [
                    "month": monthFormatter.string(from: month),
                    "income": money(AnalyticsEngine.incomeTotal(txs)),
                    "expense": money(AnalyticsEngine.expenseTotal(txs)),
                    "net": money(AnalyticsEngine.netTotal(txs)),
                    "invested": money(txs.netInvested),
                    "expense_by_category": byCategory,
                ]
            }
            return ["months": rows]
        }

        private static func forecast(context: ModelContext) throws -> Any {
            let month = Date.now.startOfMonth
            let range = monthRange(month)
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let rules = try context.fetch(FetchDescriptor<RecurringRule>())
            guard let result = AnalyticsEngine.forecast(
                month: month,
                monthTxs: all.filter { range.contains($0.date) },
                allTx: all,
                rules: rules
            ) else {
                throw MCPToolError("Not enough data to forecast this month.")
            }

            return [
                "month": monthFormatter.string(from: month),
                "days_elapsed": result.daysElapsed,
                "days_in_month": result.daysInMonth,
                "projected_net": money(result.projectedNet),
                "projected_closing_balance": money(result.projectedClosingBalance),
                "committed_so_far_net": money(result.committedSoFarNet),
                "committed_remaining_net": money(result.committedRemainingNet),
                "discretionary_so_far_net": money(result.discretionaryNetSoFar),
                "upcoming": result.upcoming.map { item -> [String: Any] in
                    ["title": item.title, "date": dateFormatter.string(from: item.date), "net_amount": money(item.amount)]
                },
            ]
        }

        // MARK: Write tools

        private static func addTransaction(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            guard let rawTitle = try stringArgument("title", in: arguments) else {
                throw MCPToolError("title is required")
            }
            guard let amount = try numberArgument("amount", in: arguments) else {
                throw MCPToolError("amount is required")
            }
            guard let categoryValue = try stringArgument("category", in: arguments) else {
                throw MCPToolError("category is required")
            }
            let title = try validatedTitle(rawTitle)
            try validateAmount(amount)
            let categories = try context.fetch(FetchDescriptor<Category>())
            let category = try resolveCategory(categoryValue, in: categories)
            let subCategory = try stringArgument("sub_category", in: arguments).flatMap { value in
                try value.isEmpty ? nil : resolveCategory(value, in: categories)
            }
            if subCategory?.id == category.id {
                throw MCPToolError("sub_category must differ from category")
            }
            let date = try dateArgument("date", in: arguments).map(storedDate) ?? .now
            try ensureUnlocked(date)
            let isReturn = try boolArgument("investment_return", in: arguments) ?? false

            let transaction = try Transaction(
                title: title,
                desc: validatedDescription(arguments),
                amount: amount,
                date: date,
                category: category,
                subCategory: subCategory,
                isInvestmentReturn: category.type == .investment && isReturn
            )
            context.insert(transaction)
            try commit(context)
            return ["transaction": serialize(transaction)]
        }

        private static func updateTransaction(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            let transaction = try resolveTransaction(arguments, context: context)
            try ensureUnlocked(transaction.date)

            let title = try stringArgument("title", in: arguments).map(validatedTitle)
            let amount = try numberArgument("amount", in: arguments)
            if let amount {
                try validateAmount(amount)
            }
            let categories = try context.fetch(FetchDescriptor<Category>())
            let category = try stringArgument("category", in: arguments).map { try resolveCategory($0, in: categories) }
            let subValue = try stringArgument("sub_category", in: arguments)
            let subCategory = try subValue.flatMap { value in
                try value.isEmpty ? nil : resolveCategory(value, in: categories)
            }
            if let subCategory, subCategory.id == (category ?? transaction.category)?.id {
                throw MCPToolError("sub_category must differ from category")
            }
            let date = try dateArgument("date", in: arguments).map(storedDate)
            if let date {
                try ensureUnlocked(date)
            }
            let hasDescription = arguments["description"] != nil
            let description = try validatedDescription(arguments)
            let isReturn = try boolArgument("investment_return", in: arguments)
            guard title != nil || amount != nil || category != nil || subValue != nil || date != nil || hasDescription || isReturn != nil else {
                throw MCPToolError("Provide at least one field to change.")
            }

            if let title {
                transaction.title = title
            }
            if let amount {
                transaction.amount = amount
            }
            if let category {
                transaction.category = category
            }
            if subValue != nil {
                transaction.subCategory = subCategory
            }
            if transaction.subCategory?.id == transaction.category?.id {
                transaction.subCategory = nil
            }
            if let date {
                transaction.date = date
            }
            if hasDescription {
                transaction.desc = description
            }
            if let isReturn {
                transaction.isInvestmentReturn = isReturn
            }
            if !transaction.isInvestment {
                transaction.isInvestmentReturn = false
            }
            try commit(context)
            return ["transaction": serialize(transaction)]
        }

        private static func deleteTransaction(_ arguments: [String: Any], context: ModelContext) throws -> Any {
            let transaction = try resolveTransaction(arguments, context: context)
            try ensureUnlocked(transaction.date)
            let deleted = serialize(transaction)
            context.delete(transaction)
            try commit(context)
            return ["deleted": deleted]
        }

        private static func commit(_ context: ModelContext) throws {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw MCPToolError("Could not save: \(error.localizedDescription)")
            }
            WidgetSnapshotWriter.write(context: context)
        }

        // MARK: Validation

        private static func validatedTitle(_ raw: String) throws -> String {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= maxTitleLength else {
                throw MCPToolError("title must be 1-\(maxTitleLength) characters")
            }
            return title
        }

        private static func validatedDescription(_ arguments: [String: Any]) throws -> String? {
            guard let raw = try stringArgument("description", in: arguments) else { return nil }
            let description = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard description.count <= maxDescriptionLength else {
                throw MCPToolError("description must be at most \(maxDescriptionLength) characters")
            }
            return description.isEmpty ? nil : description
        }

        private static func validateAmount(_ amount: Double) throws {
            guard amount.isFinite, amount > 0, amount <= maxAmount else {
                throw MCPToolError("amount must be a positive number")
            }
        }

        private static func ensureUnlocked(_ date: Date) throws {
            if date.isInPastMonth {
                throw MCPToolError("Transactions in past months are locked.")
            }
        }

        private static func resolveTransaction(_ arguments: [String: Any], context: ModelContext) throws -> Transaction {
            guard let value = try stringArgument("id", in: arguments), let id = UUID(uuidString: value) else {
                throw MCPToolError("id must be a transaction id")
            }
            var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let transaction = try context.fetch(descriptor).first else {
                throw MCPToolError("No transaction with id \(value)")
            }
            return transaction
        }

        private static func resolveCategory(_ value: String, in categories: [Category]) throws -> Category {
            if let id = UUID(uuidString: value), let match = categories.first(where: { $0.id == id }) {
                return match
            }
            let matches = categories.filter { $0.name.compare(value, options: .caseInsensitive) == .orderedSame }
            if matches.count > 1 {
                throw MCPToolError("More than one category is named \(value). Use its id from list_categories.")
            }
            guard let match = matches.first else {
                throw MCPToolError("No category named \(value). Available: \(categories.map(\.name).sorted().joined(separator: ", "))")
            }
            return match
        }

        // MARK: Arguments

        private static func stringArgument(_ key: String, in arguments: [String: Any]) throws -> String? {
            guard let value = arguments[key], !(value is NSNull) else { return nil }
            guard let string = value as? String else {
                throw MCPToolError("\(key) must be a string")
            }
            return string
        }

        private static func numberArgument(_ key: String, in arguments: [String: Any]) throws -> Double? {
            guard let value = arguments[key], !(value is NSNull) else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                throw MCPToolError("\(key) must be a number")
            }
            return number.doubleValue
        }

        private static func boolArgument(_ key: String, in arguments: [String: Any]) throws -> Bool? {
            guard let value = arguments[key], !(value is NSNull) else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw MCPToolError("\(key) must be true or false")
            }
            return number.boolValue
        }

        private static func integerArgument(_ key: String, in arguments: [String: Any], range: ClosedRange<Int>) throws -> Int? {
            guard let number = try numberArgument(key, in: arguments) else { return nil }
            guard let integer = Int(exactly: number), range.contains(integer) else {
                throw MCPToolError("\(key) must be a whole number between \(range.lowerBound) and \(range.upperBound)")
            }
            return integer
        }

        private static func dateArgument(_ key: String, in arguments: [String: Any]) throws -> Date? {
            guard let value = try stringArgument(key, in: arguments) else { return nil }
            guard let date = dateFormatter.date(from: value) else {
                throw MCPToolError("\(key) must be a valid date as yyyy-MM-dd")
            }
            return date
        }

        private static func monthArgument(_ key: String, in arguments: [String: Any]) throws -> Date? {
            guard let value = try stringArgument(key, in: arguments) else { return nil }
            guard let month = monthFormatter.date(from: value) else {
                throw MCPToolError("\(key) must be a valid month as yyyy-MM")
            }
            return month
        }

        // MARK: Formatting

        private static let dateFormatter = makeFormatter("yyyy-MM-dd")
        private static let monthFormatter = makeFormatter("yyyy-MM")

        private static func makeFormatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }

        private static func serialize(_ transaction: Transaction) -> [String: Any] {
            [
                "id": transaction.id.uuidString,
                "title": transaction.title,
                "description": nullable(transaction.desc),
                "amount": money(transaction.amount),
                "type": nullable(transaction.category?.type.rawValue),
                "investment_return": transaction.isInvestmentReturn,
                "category": nullable(transaction.category?.name),
                "sub_category": nullable(transaction.subCategory?.name),
                "date": dateFormatter.string(from: transaction.date),
                "recurring": transaction.recurringRuleID != nil,
                "locked": transaction.date.isInPastMonth,
            ]
        }

        private static func storedDate(_ day: Date) -> Date {
            Calendar.current.isDateInToday(day) ? .now : day
        }

        private static func monthRange(_ month: Date) -> Range<Date> {
            let start = month.startOfMonth
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? month.endOfMonth
            return start ..< end
        }

        private static func balance(of transactions: [Transaction]) -> Double {
            transactions.reduce(OpeningBalance.amount) { $0 + $1.signedCashAmount }
        }

        private static func money(_ value: Double) -> Double {
            (value * 100).rounded() / 100
        }

        private static func nullable(_ value: (some Any)?) -> Any {
            value.map { $0 as Any } ?? NSNull()
        }
    }
#endif
