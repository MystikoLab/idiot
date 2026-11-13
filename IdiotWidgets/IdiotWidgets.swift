import SwiftUI
import WidgetKit

@main
struct IdiotWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransactionWidget()
        AnalyticsWidget()
        NewTransactionWidget()
        SavingsGoalsWidget()
        QuickLogWidget()
        #if os(iOS)
            if #available(iOS 18.0, *) {
                LogTransactionControl()
            }
        #endif
    }
}
