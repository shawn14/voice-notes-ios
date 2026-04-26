import Foundation
import CoreData
import CloudKit

struct CloudKitEventLogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let type: String
    let succeeded: Bool
    let errorDescription: String?
}

enum CloudKitEventLog {
    private static let key = "cloudKitEventLog_v1"
    private static let maxEntries = 10

    static func register() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

            let typeString: String
            switch event.type {
            case .setup:  typeString = "setup"
            case .import: typeString = "import"
            case .export: typeString = "export"
            @unknown default: typeString = "unknown"
            }

            let entry = CloudKitEventLogEntry(
                id: UUID(),
                date: event.endDate ?? event.startDate,
                type: typeString,
                succeeded: event.succeeded,
                errorDescription: formatError(event.error)
            )
            append(entry)
        }
    }

    static func recent() -> [CloudKitEventLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CloudKitEventLogEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func formatError(_ error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError

        if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            let header = "partialFailure × \(partial.count) record(s):"
            let lines = partial.prefix(5).map { (id, err) -> String in
                let nsErr = err as NSError
                let recordName = describeID(id)
                let codeName = ckCodeName(nsErr.code)
                let msg = nsErr.localizedDescription
                return "• \(recordName) → \(codeName) — \(msg)"
            }
            return ([header] + Array(lines)).joined(separator: "\n")
        }

        if nsError.domain == CKError.errorDomain {
            return "\(ckCodeName(nsError.code)) — \(nsError.localizedDescription)"
        }

        return nsError.localizedDescription
    }

    private static func ckCodeName(_ code: Int) -> String {
        guard let c = CKError.Code(rawValue: code) else { return "CKError(\(code))" }
        return String(describing: c)
    }

    private static func describeID(_ id: AnyHashable) -> String {
        if let recordID = id.base as? CKRecord.ID {
            let name = recordID.recordName
            return name.count > 12 ? String(name.prefix(12)) + "…" : name
        }
        let s = String(describing: id.base)
        return s.count > 20 ? String(s.prefix(20)) + "…" : s
    }

    private static func append(_ entry: CloudKitEventLogEntry) {
        var entries = recent()
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
