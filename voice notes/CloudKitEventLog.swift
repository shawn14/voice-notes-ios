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
        switch c {
        case .internalError: return "internalError"
        case .partialFailure: return "partialFailure"
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .badContainer: return "badContainer"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .missingEntitlement: return "missingEntitlement"
        case .notAuthenticated: return "notAuthenticated"
        case .permissionFailure: return "permissionFailure"
        case .unknownItem: return "unknownItem"
        case .invalidArguments: return "invalidArguments"
        case .resultsTruncated: return "resultsTruncated"
        case .serverRecordChanged: return "serverRecordChanged"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .assetFileNotFound: return "assetFileNotFound"
        case .assetFileModified: return "assetFileModified"
        case .incompatibleVersion: return "incompatibleVersion"
        case .constraintViolation: return "constraintViolation"
        case .operationCancelled: return "operationCancelled"
        case .changeTokenExpired: return "changeTokenExpired"
        case .batchRequestFailed: return "batchRequestFailed"
        case .zoneBusy: return "zoneBusy"
        case .badDatabase: return "badDatabase"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotFound: return "zoneNotFound"
        case .limitExceeded: return "limitExceeded"
        case .userDeletedZone: return "userDeletedZone"
        case .tooManyParticipants: return "tooManyParticipants"
        case .alreadyShared: return "alreadyShared"
        case .referenceViolation: return "referenceViolation"
        case .managedAccountRestricted: return "managedAccountRestricted"
        case .participantMayNeedVerification: return "participantMayNeedVerification"
        case .serverResponseLost: return "serverResponseLost"
        case .assetNotAvailable: return "assetNotAvailable"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        @unknown default: return "CKError(\(code))"
        }
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
