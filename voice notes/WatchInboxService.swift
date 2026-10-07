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
//  launch and makes a note for a `watch-*.m4a` that was never ingested.
//
//  "Never ingested" is decided by a ledger of recording ids (UserDefaults),
//  not by "no note points at this file". A note can be missing for ordinary
//  reasons: it was deleted on another device, purged from Recently Deleted,
//  or the local store is being re-downloaded from iCloud. Adopting on that
//  evidence would bring deleted notes back and duplicate synced ones. The
//  ledger also stops a recording the watch sends twice from returning after
//  the user removed it.
//

import Foundation
import SwiftData
import WatchConnectivity

final class WatchInboxService: NSObject {
    static let shared = WatchInboxService()

    nonisolated static let filePrefix = "watch-"

    // MARK: Ledger of recordings already turned into notes

    nonisolated private static let ledgerKey = "watchInboxIngestedIDs"
    /// Far more than the files that can be in flight; keeps the list bounded.
    nonisolated private static let ledgerLimit = 2_000

    nonisolated static func wasIngested(_ fileName: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: ledgerKey) ?? []).contains(fileName)
    }

    nonisolated static func markIngested(_ fileName: String) {
        var ids = UserDefaults.standard.stringArray(forKey: ledgerKey) ?? []
        guard !ids.contains(fileName) else { return }
        ids.append(fileName)
        UserDefaults.standard.set(Array(ids.suffix(ledgerLimit)), forKey: ledgerKey)
    }

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
        guard !wasIngested(name), !FileManager.default.fileExists(atPath: destination.path) else { return nil }
        do {
            try FileManager.default.moveItem(at: received, to: destination)
            return destination
        } catch {
            print("[WatchInbox] could not keep a watch recording: \(error.localizedDescription)")
            return nil
        }
    }

    /// Make the note for a claimed recording, once.
    fileprivate func ingest(_ file: URL, recordedAt: Date?, duration: Double?) async {
        let name = file.lastPathComponent
        guard !Self.wasIngested(name) else { return }
        // Recorded before the note exists: a crash in between leaves a file
        // with no note, which is recoverable by hand, instead of a duplicate
        // note on every launch, which is not.
        Self.markIngested(name)
        await BackgroundCaptureService.shared.ingestRecording(at: file, recordedAt: recordedAt, duration: duration)
    }

    private func adoptStrandedRecordings() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: Self.documents, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == "m4a" }
            .filter { !Self.wasIngested($0.lastPathComponent) }
        for file in files {
            let recordedAt = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
            Task { await ingest(file, recordedAt: recordedAt, duration: nil) }
        }
    }
}

extension WatchInboxService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Synchronous: the system removes `file.fileURL` when this returns.
        guard let destination = Self.claim(file.fileURL, id: file.metadata?["id"] as? String) else { return }
        let recordedAt = file.metadata?["recordedAt"] as? Date
        let duration = file.metadata?["duration"] as? Double
        Task { @MainActor in
            await WatchInboxService.shared.ingest(destination, recordedAt: recordedAt, duration: duration)
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
