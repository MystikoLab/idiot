import SwiftUI

extension EnvironmentValues {
    @Entry var amountsHidden = false
}

private struct MaskedAmountModifier: ViewModifier {
    @Environment(\.amountsHidden) private var amountsHidden

    func body(content: Content) -> some View {
        content
            .redacted(reason: amountsHidden ? .placeholder : [])
            .accessibilityHidden(amountsHidden)
    }
}

extension View {
    func maskedAmount() -> some View {
        modifier(MaskedAmountModifier())
    }
}
