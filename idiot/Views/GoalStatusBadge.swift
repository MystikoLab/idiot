import SwiftUI

extension GoalEngine.Status {
    var color: Color {
        switch self {
        case .reached: .green
        case .onTrack: .blue
        case .behind: .orange
        case .open: .secondary
        }
    }

    var iconName: String {
        switch self {
        case .reached: "checkmark.circle.fill"
        case .onTrack: "arrow.up.right.circle.fill"
        case .behind: "exclamationmark.circle.fill"
        case .open: "circle.dotted"
        }
    }
}

struct GoalStatusBadge: View {
    let status: GoalEngine.Status

    var body: some View {
        Label(status.label, systemImage: status.iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .lineLimit(1)
    }
}

struct GoalIcon: View {
    let iconName: String
    let colorHex: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(hex: colorHex))
            .frame(width: size, height: size)
            .background(Color(hex: colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

extension GoalEngine.Progress {
    var amountText: String {
        "\(saved.formattedCurrency) of \(target.formattedCurrency)"
    }

    var tint: Color {
        status == .reached ? .green : Color(hex: colorHex)
    }

    var paceText: String? {
        guard let deadline else { return nil }
        let date = deadline.formatted(.dateTime.day().month(.abbreviated).year())
        if status == .reached {
            return nil
        }
        guard let requiredMonthly else {
            return "Deadline \(date) has passed"
        }
        return "Save \(requiredMonthly.formattedCurrency)/month to hit it by \(date)"
    }
}
