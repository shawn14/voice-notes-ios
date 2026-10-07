//
//  WatchInboxService.swift
//  voice notes
//
//  Receives recordings made on the Apple Watch (EEONWatch target) and turns
//  each into a note through the same save-first pipeline as a widget capture.
//
//  WatchConnectivity deletes a received file as soon as the delegate call
//  returns, so the file is moved into Documents synchronously, before anything
//  else. Its name is the recording's id (`watch-<uuid>.m4a`, chosen on the
//  watch), which makes a re-sent recording a no-op.
//
//  If the app dies between the move and the note being saved, the recording
//  would sit in Documents with no note. `adoptStrandedRecordings` runs at
//  launch and makes a note for any `watch-*.m4a` nothing points to.
//

import Foundation
import SwiftData
import WatchConnectivity

final class WatchInboxService: NSObject {
    static let shared = WatchInboxService()

    nonisolated static let filePrefix = "watch-"

    private var container: ModelContainer?

    func configure(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        adoptStrandedRecordings()
    }

    nonisolated private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Move a received recording into Documents. Returns the destination, or
    /// nil when this recording id is already there (a repeat delivery) or the
    /// move failed.
    nonisolated static func claim(_ received: URL, id: String?) -> URL? {
        let name: String = {
            if let id, id.hasPrefix(filePrefix), !id.contains("/") { return id + ".m4a" }
            return filePrefix + UUID().uuidString + ".m4a"
        }()
        let destination = documents.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }
        do {
            try FileManager.default.moveItem(at: received, to: destination)
            return destination
        } catch {
            print("[WatchInbox] could not keep a watch recording: \(error.localizedDescription)")
            return nil
        }
    }

    private func adoptStrandedRecordings() {
        guard let container else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(at: Self.documents, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == "m4a" }
        guard !files.isEmpty else { return }

        let known = Set(((try? container.mainContext.fetch(FetchDescriptor<Note>())) ?? []).compactMap(\.audioFileName))
        // A recording waiting in Recently Deleted belongs to a note too.
        let binned = Set(RecentlyDeletedStore.entries().compactMap(\.audioFileName))
        for file in files where !known.contains(file.lastPathComponent) && !binned.contains(file.lastPathComponent) {
            let recordedAt = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
            Task { await BackgroundCaptureService.shared.ingestRecording(at: file, recordedAt: recordedAt) }
        }
    }
}

extension WatchInboxService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Synchronous: the system removes `file.fileURL` when this returns.
        guard let destination = Self.claim(file.fileURL, id: file.metadata?["id"] as? String) else { return }
        let recordedAt = file.metadata?["recordedAt"] as? Date
        Task { @MainActor in
            await BackgroundCaptureService.shared.ingestRecording(at: destination, recordedAt: recordedAt)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchInbox] activation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches; reconnect to the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
