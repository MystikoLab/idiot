import Foundation

enum GoalEngine {
    enum Status: String {
        case reached
        case onTrack
        case behind
        case open

        var label: String {
            switch self {
            case .reached: "Reached"
            case .onTrack: "On track"
            case .behind: "Behind"
            case .open: "In progress"
            }
        }
    }

    struct Progress: Identifiable {
        let id: UUID
        let name: String
        let iconName: String
        let colorHex: String
        let categoryName: String?
        let target: Double
        let saved: Double
        let startDate: Date
        let deadline: Date?
        let status: Status
        let requiredMonthly: Double?
        let projectedCompletion: Date?

        var fraction: Double {
            target > 0 ? min(max(saved / target, 0), 1) : 0
        }

        var percent: Int {
            Int((fraction * 100).rounded(.down))
        }

        var remaining: Double {
            max(target - saved, 0)
        }
    }

    struct SeriesPoint: Identifiable {
        let date: Date
        let saved: Double

        var id: Date {
            date
        }
    }

    static let daysPerMonth = 30.4375

    static func contribution(of transaction: Transaction) -> Double {
        transaction.isInvestment ? transaction.investedAmount : transaction.amount
    }

    static func counted(_ transactions: [Transaction], categoryID: UUID?, from start: Date) -> [Transaction] {
        guard let categoryID else { return [] }
        let startDay = Calendar.current.startOfDay(for: start)
        return transactions.filter { $0.category?.id == categoryID && $0.date >= startDay }
    }

    static func savedAmount(_ transactions: [Transaction], categoryID: UUID?, from start: Date) -> Double {
        counted(transactions, categoryID: categoryID, from: start).reduce(0) { $0 + contribution(of: $1) }
    }

    static func expectedAmount(target: Double, start: Date, deadline: Date, now: Date) -> Double {
        let startDay = Calendar.current.startOfDay(for: start)
        let total = deadline.timeIntervalSince(startDay)
        guard total > 0 else { return target }
        let elapsed = min(max(now.timeIntervalSince(startDay), 0), total)
        return target * elapsed / total
    }

    static func status(saved: Double, target: Double, start: Date, deadline: Date?, now: Date) -> Status {
        if target > 0, saved >= target {
            return .reached
        }
        guard let deadline else { return .open }
        return saved >= expectedAmount(target: target, start: start, deadline: deadline, now: now) ? .onTrack : .behind
    }

    static func requiredMonthly(saved: Double, target: Double, deadline: Date?, now: Date) -> Double? {
        guard let deadline, deadline > now, saved < target else { return nil }
        let months = deadline.timeIntervalSince(now) / 86400 / daysPerMonth
        return (target - saved) / max(months, 1)
    }

    static func projectedCompletion(saved: Double, target: Double, start: Date, now: Date) -> Date? {
        let startDay = Calendar.current.startOfDay(for: start)
        let elapsedDays = now.timeIntervalSince(startDay) / 86400
        guard saved > 0, saved < target, elapsedDays >= 1 else { return nil }
        let monthlyAverage = saved / max(elapsedDays / daysPerMonth, 1)
        let daysLeft = (target - saved) / monthlyAverage * daysPerMonth
        guard daysLeft.isFinite, daysLeft < 36500 else { return nil }
        return now.addingTimeInterval(daysLeft * 86400)
    }

    static func cumulativeSeries(_ transactions: [Transaction], categoryID: UUID?, from start: Date, now: Date) -> [SeriesPoint] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        var daily: [Date: Double] = [startDay: 0]
        for transaction in counted(transactions, categoryID: categoryID, from: start) {
            daily[calendar.startOfDay(for: transaction.date), default: 0] += contribution(of: transaction)
        }

        var running = 0.0
        var points = daily.keys.sorted().map { day -> SeriesPoint in
            running += daily[day] ?? 0
            return SeriesPoint(date: day, saved: running)
        }
        if let last = points.last, last.date < now {
            points.append(SeriesPoint(date: now, saved: last.saved))
        }
        return points
    }

    static func progress(for goal: SavingsGoal, now: Date = .now) -> Progress {
        let category = goal.category
        let saved = savedAmount(category?.transactions ?? [], categoryID: category?.id, from: goal.startDate)
        return Progress(
            id: goal.id,
            name: goal.name,
            iconName: goal.iconName,
            colorHex: goal.colorHex,
            categoryName: category?.name,
            target: goal.targetAmount,
            saved: saved,
            startDate: goal.startDate,
            deadline: goal.deadline,
            status: status(saved: saved, target: goal.targetAmount, start: goal.startDate, deadline: goal.deadline, now: now),
            requiredMonthly: requiredMonthly(saved: saved, target: goal.targetAmount, deadline: goal.deadline, now: now),
            projectedCompletion: projectedCompletion(saved: saved, target: goal.targetAmount, start: goal.startDate, now: now)
        )
    }

    static func series(for goal: SavingsGoal, now: Date = .now) -> [SeriesPoint] {
        cumulativeSeries(goal.category?.transactions ?? [], categoryID: goal.category?.id, from: goal.startDate, now: now)
    }
}
