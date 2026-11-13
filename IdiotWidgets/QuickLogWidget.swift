import AppIntents
import SwiftUI
import WidgetKit

struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let description = IntentDescription("Logs one of your frequent transactions for today.")
    static let isDiscoverable = false

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        WidgetStore.logFrequent(itemID: itemID)
        return .result()
    }
}

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLogWidget", provider: StaticProvider()) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("Log your most frequent transactions with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StaticEntry

    private var items: [SnapshotFrequent] {
        Array((entry.snapshot.frequent ?? []).prefix(family == .systemSmall ? 2 : 4))
    }

    private var rows: [[SnapshotFrequent]] {
        guard family != .systemSmall else { return items.map { [$0] } }
        return stride(from: 0, to: items.count, by: 2).map { Array(items[$0 ..< min($0 + 2, items.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(row) { item in
                                button(for: item)
                            }
                            if family != .systemSmall, row.count == 1 {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.add)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Quick Log")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if family == .systemSmall {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            } else {
                AddLink(size: .title3)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "bolt.badge.clock")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Log something twice and it shows up here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isLogged(_ item: SnapshotFrequent) -> Bool {
        guard let logged = entry.snapshot.lastLogged, logged.itemID == item.id else { return false }
        return entry.date.timeIntervalSince(logged.date) < WidgetStore.feedbackDuration
    }

    private func button(for item: SnapshotFrequent) -> some View {
        let logged = isLogged(item)
        let tint = Color(snapshotHex: item.colorHex)
        return Button(intent: QuickLogIntent(itemID: item.id)) {
            HStack(spacing: 8) {
                Image(systemName: logged ? "checkmark.circle.fill" : item.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(logged ? Color.green : tint)
                    .frame(width: 20)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(logged ? "Logged" : "\(item.isIncome ? "+" : "")\(item.amount.widgetCurrency)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive(!logged)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(logged ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(logged ? "\(item.title) logged" : "Log \(item.title), \(item.amount.widgetCurrency)")
    }
}

#if os(iOS)
    @available(iOS 18.0, *)
    struct LogTransactionControl: ControlWidget {
        var body: some ControlWidgetConfiguration {
            StaticControlConfiguration(kind: "LogTransactionControl") {
                ControlWidgetButton(action: OpenAddFormIntent()) {
                    Label("Log Transaction", systemImage: "plus.circle.fill")
                }
            }
            .displayName("Log Transaction")
            .description("Opens Idiot on the new transaction form.")
        }
    }
#endif
