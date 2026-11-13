import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.umangsurana.idiot"))
            return try ModelContainer(
                for: Category.self, Transaction.self, RecurringRule.self, Attachment.self, SavingsGoal.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }()
}
