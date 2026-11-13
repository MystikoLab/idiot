import SwiftUI

struct GoalsSection: View {
    let goals: [GoalEngine.Progress]
    let series: [UUID: [GoalEngine.SeriesPoint]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Savings Goals")
                .font(.headline)

            if goals.isEmpty {
                ContentUnavailableView(
                    "No savings goals yet",
                    systemImage: "target",
                    description: Text("Add a goal in Settings > Savings Goals to track it here.")
                )
            } else {
                Text("Goals count every transaction in their linked category since the start date and ignore the filters above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(goals) { goal in
                        GoalCardView(progress: goal, series: series[goal.id] ?? [])
                    }
                }
            }
        }
    }
}
