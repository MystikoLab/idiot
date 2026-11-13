import SwiftData
import SwiftUI

struct GoalsStripView: View {
    @Environment(\.openURL) private var openURL
    @Query(sort: \SavingsGoal.sortOrder) private var goals: [SavingsGoal]

    #if os(macOS)
        private let visibleLimit = 3
    #else
        private let visibleLimit = 2
    #endif

    private var activeGoals: [SavingsGoal] {
        goals.activeOrdered
    }

    private var visible: [GoalEngine.Progress] {
        activeGoals.prefix(visibleLimit).map { GoalEngine.progress(for: $0) }
    }

    private var hiddenCount: Int {
        max(activeGoals.count - visibleLimit, 0)
    }

    var body: some View {
        if !activeGoals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                header
                tiles
            }
        }
    }

    private var header: some View {
        Button {
            openGoals()
        } label: {
            HStack(spacing: 4) {
                Text("Goals")
                    .font(.caption.weight(.semibold))
                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more")
                        .font(.caption)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens goals in Analytics")
    }

    private var tiles: some View {
        #if os(macOS)
            HStack(spacing: 8) {
                ForEach(visible) { progress in
                    GoalStripTile(progress: progress)
                }
            }
        #else
            VStack(spacing: 8) {
                ForEach(visible) { progress in
                    GoalStripTile(progress: progress)
                }
            }
        #endif
    }

    private func openGoals() {
        if let url = URL(string: "idiot://goals") {
            openURL(url)
        }
    }
}

private struct GoalStripTile: View {
    let progress: GoalEngine.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: progress.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: progress.colorHex))
                    .accessibilityHidden(true)
                Text(progress.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                GoalStatusBadge(status: progress.status)
                    .labelStyle(.titleOnly)
            }

            ProgressView(value: progress.fraction)
                .tint(progress.tint)
                .accessibilityLabel("\(progress.name) progress")
                .accessibilityValue("\(progress.percent) percent")

            Text(progress.categoryName == nil ? "No category linked" : progress.amountText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .maskedAmount()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
