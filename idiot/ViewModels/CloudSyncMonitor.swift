import CloudKit
import CoreData
import Observation

@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()
    private static let containerIdentifier = "iCloud.com.umangsurana.idiot"

    private(set) var accountAvailable: Bool?
    private(set) var activeEvent: NSPersistentCloudKitContainer.EventType?
    private(set) var lastEvent: NSPersistentCloudKitContainer.Event?
    private(set) var lastErrorMessage: String?

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        Task { await refreshAccountStatus() }

        Task {
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                handle(notification)
            }
        }
    }

    func refreshAccountStatus() async {
        do {
            let status = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            accountAvailable = status == .available
        } catch {
            accountAvailable = false
        }
    }

    private func handle(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        if event.endDate == nil {
            activeEvent = event.type
            return
        }

        activeEvent = nil
        lastEvent = event
        lastErrorMessage = event.error.map(Self.failureMessage)

        if event.type == .import, event.error == nil {
            NotificationManager.shared.refresh()
        }

        #if DEBUG
            print("[CloudSync] \(Self.name(for: event.type)) finished — error: \(lastErrorMessage ?? "none")")
        #endif
    }

    var statusText: String {
        if let activeEvent {
            return "\(Self.progressLabel(for: activeEvent))…"
        }
        if let lastEvent, let lastErrorMessage {
            return "\(Self.name(for: lastEvent.type)) failed: \(lastErrorMessage)"
        }
        if let lastEvent {
            let time = lastEvent.endDate?.formatted(date: .omitted, time: .shortened) ?? ""
            return "\(Self.name(for: lastEvent.type)) ✓ \(time)"
        }
        switch accountAvailable {
        case .some(true):
            return "Ready"
        case .some(false):
            return "iCloud unavailable"
        case .none:
            return "Checking iCloud…"
        }
    }

    var showsError: Bool {
        lastErrorMessage != nil || accountAvailable == false
    }

    private static let quotaMessage = "iCloud storage is full — free up space or upgrade your plan; sync will retry automatically"

    private static func failureMessage(for error: Error) -> String {
        var messages: [String] = []
        var sawQuota = false
        var visited = Set<ObjectIdentifier>()
        var queue: [Error] = [error]

        while let current = queue.popLast() {
            let nsError = current as NSError
            let id = ObjectIdentifier(nsError)
            guard !visited.contains(id) else { continue }
            visited.insert(id)

            if nsError.domain == CKErrorDomain, nsError.code == CKError.quotaExceeded.rawValue {
                sawQuota = true
            }

            if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any] {
                for value in partial.values {
                    if let subError = value as? Error {
                        queue.append(subError)
                    }
                }
            }

            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying)
            } else if nsError.domain != CKErrorDomain {
                messages.append(nsError.localizedDescription)
            }
        }

        if sawQuota {
            return quotaMessage
        }

        var seen = Set<String>()
        messages = messages.filter { seen.insert($0).inserted }

        if messages.isEmpty {
            let nsError = error as NSError
            if nsError.domain == CKErrorDomain, nsError.code == CKError.partialFailure.rawValue {
                return "Upload failed — iCloud storage may be full or temporarily unavailable. Free up space or check your connection; sync will retry automatically"
            }
            return nsError.localizedDescription
        }

        return messages.joined(separator: " · ")
    }

    private static func progressLabel(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "Setting up iCloud sync"
        case .import: "Downloading changes"
        case .export: "Uploading changes"
        @unknown default: "Syncing"
        }
    }

    private static func name(for type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "Sync set up"
        case .import: "Refreshed"
        case .export: "Uploaded"
        @unknown default: "Synced"
        }
    }
}
