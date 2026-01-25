//
//  CloudKitShareService.swift
//  voice notes
//
//  Handles sharing notes via CloudKit public database
//  Recipients can view/listen via Universal Link, signup to use app
//

import Foundation
import CloudKit

/// Represents a shared note in CloudKit
struct SharedNote: Identifiable {
    let id: String  // CKRecord.ID.recordName
    let title: String
    let content: String
    let audioURL: URL?
    let createdAt: Date
    let expiresAt: Date?

    var shareURL: URL? {
        // Universal Link format: https://yourdomain.com/share/{id}
        // For now, use a custom URL scheme that can be upgraded later
        URL(string: "voicenotes://share/\(id)")
    }
}

actor CloudKitShareService {
    static let shared = CloudKitShareService()

    private let container: CKContainer
    private let publicDB: CKDatabase

    // Record type name in CloudKit
    private let recordType = "SharedNote"

    private init() {
        // Use the default container (configured in Xcode capabilities)
        self.container = CKContainer.default()
        self.publicDB = container.publicCloudDatabase
    }

    // MARK: - Share a Note

    /// Upload a note to CloudKit and return a shareable link
    func shareNote(
        title: String,
        content: String,
        audioFileURL: URL?,
        expiresIn days: Int? = 30
    ) async throws -> SharedNote {
        // Create the record
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record["title"] = title
        record["content"] = content
        record["createdAt"] = Date()

        if let days = days {
            record["expiresAt"] = Date().addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
        }

        // Upload audio as CKAsset if provided
        if let audioURL = audioFileURL {
            let asset = CKAsset(fileURL: audioURL)
            record["audio"] = asset
        }

        // Save to public database
        let savedRecord = try await publicDB.save(record)

        // Build the SharedNote result
        var audioDownloadURL: URL? = nil
        if let asset = savedRecord["audio"] as? CKAsset {
            audioDownloadURL = asset.fileURL
        }

        return SharedNote(
            id: savedRecord.recordID.recordName,
            title: title,
            content: content,
            audioURL: audioDownloadURL,
            createdAt: Date(),
            expiresAt: savedRecord["expiresAt"] as? Date
        )
    }

    // MARK: - Fetch a Shared Note

    /// Retrieve a shared note by ID (for recipients)
    func fetchSharedNote(id: String) async throws -> SharedNote? {
        let recordID = CKRecord.ID(recordName: id)

        do {
            let record = try await publicDB.record(for: recordID)

            // Check expiration
            if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                // Note has expired - delete it and return nil
                _ = try? await publicDB.deleteRecord(withID: recordID)
                return nil
            }

            var audioURL: URL? = nil
            if let asset = record["audio"] as? CKAsset {
                audioURL = asset.fileURL
            }

            return SharedNote(
                id: record.recordID.recordName,
                title: record["title"] as? String ?? "",
                content: record["content"] as? String ?? "",
                audioURL: audioURL,
                createdAt: record["createdAt"] as? Date ?? Date(),
                expiresAt: record["expiresAt"] as? Date
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil  // Note doesn't exist or was deleted
        }
    }

    // MARK: - Delete a Shared Note

    /// Remove a shared note (owner only)
    func deleteSharedNote(id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await publicDB.deleteRecord(withID: recordID)
    }

    // MARK: - Check CloudKit Availability

    func checkAccountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

// MARK: - Share URL Generation

extension SharedNote {
    /// Generate a shareable URL
    /// In production, this would be a Universal Link to your domain
    /// For now, uses a custom URL scheme
    var shareableURL: URL {
        // Production format would be:
        // https://voicenotes.app/share/{id}

        // Development format (custom scheme):
        URL(string: "voicenotes://share/\(id)")!
    }

    /// Generate share text with link
    var shareText: String {
        var text = ""
        if !title.isEmpty {
            text += "\(title)\n\n"
        }
        text += "Listen to my voice note:\n\(shareableURL.absoluteString)"
        return text
    }
}
