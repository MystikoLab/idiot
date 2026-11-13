import SwiftUI

struct RepeatSpendingSection: View {
    let groups: [AnalyticsEngine.RepeatGroup]
    let onSelect: (AnalyticsEngine.RepeatGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat Spending")
                .font(.headline)

            if groups.isEmpty {
                ContentUnavailableView(
                    "No repeat spending",
                    systemImage: "repeat",
                    description: Text("Expenses with the same name that occur at least twice in this range show up here.")
                )
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            Button {
                                onSelect(group)
                            } label: {
                                groupRow(group)
                            }
                            .buttonStyle(.plain)

                            if group.id != groups.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func groupRow(_ group: AnalyticsEngine.RepeatGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: group.colorHex))
                .frame(width: 26, height: 26)
                .background(Color(hex: group.colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(group.categoryName) · \(group.count)× · avg \(group.average.formattedCurrency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .maskedAmount()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(group.total.formattedCurrency)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("\(group.monthlyCost.formattedCurrency)/mo")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .maskedAmount()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.callout)
        .contentShape(Rectangle())
    }
}
