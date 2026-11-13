import Foundation
import SwiftData

@Model
final class Attachment {
    var id: UUID = UUID()
    var filename: String = ""
    var contentType: String = "public.jpeg"
    @Attribute(.externalStorage) var data: Data?
    var createdAt: Date = Date()
    var syncStamp: Date = Date()
    var transaction: Transaction?

    init(
        id: UUID = UUID(),
        filename: String = "",
        contentType: String = "public.jpeg",
        data: Data? = nil,
        createdAt: Date = .now,
        transaction: Transaction? = nil
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.data = data
        self.createdAt = createdAt
        self.transaction = transaction
    }
}

extension Attachment {
    var file: ReceiptFile? {
        guard let data else { return nil }
        return ReceiptFile(id: id, filename: filename, contentType: contentType, data: data)
    }
}

extension Transaction {
    var hasAttachments: Bool {
        attachments?.isEmpty == false
    }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}
