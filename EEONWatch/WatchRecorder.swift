//
//  WatchRecorder.swift
//  EEONWatch
//
//  Records to a file on the watch, then queues it for the iPhone with
//  WCSession.transferFile. The system delivers queued files in the background,
//  even if this app is closed and the phone is out of range at the time.
//
//  A recording is deleted from the watch only after the system confirms the
//  transfer finished. Anything still on disk at launch that is not already
//  queued is queued again; the phone ignores a recording id it already has.
//
//  The file name is the recording's id: `watch-<uuid>.m4a`. The iPhone side
//  (WatchInboxService) keeps that name, which is how it de-duplicates.
//

import AVFoundation
import Foundation
import Observation
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WatchRecorder: NSObject {
    private(set) var startedAt: Date?
    private(set) var waitingCount = 0
    private(set) var problem: String?
    private(set) var lastSentAt: Date?

    var isRecording: Bool { startedAt != nil }
    var statusIsProblem: Bool { problem != nil }

    var statusLine: String {
        if let problem { return problem }
        if isRecording { return "Tap to stop" }
        if waitingCount == 1 { return "1 note waiting for iPhone" }
        if waitingCount > 1 { return "\(waitingCount) notes waiting for iPhone" }
        if lastSentAt != nil { return "Sent to iPhone" }
        return "Tap to record a note"
    }

    /// Shorter than this is a mis-tap, not a note (matches the phone's guard).
    static let minimumDuration: TimeInterval = 0.8

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    static var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: Lifecycle

    func activate() {
        guard let session else {
            problem = "Can't reach iPhone"
            return
        }
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        } else {
            requeueStranded()
        }
    }

    // MARK: Recording

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        problem = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Allow the microphone in Settings"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)

            try FileManager.default.createDirectory(at: Self.recordingsDirectory, withIntermediateDirectories: true)
            let url = Self.recordingsDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
            // Speech-sized AAC: about 15 MB an hour, small enough to hand to the phone.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.record() else {
                problem = "Couldn't start recording"
                return
            }
            self.recorder = recorder
            currentURL = url
            startedAt = Date()
            WKInterfaceDevice.current().play(.start)
        } catch {
            problem = "Couldn't start recording"
        }
    }

    private func stop() {
        guard let recorder, let url = currentURL, let startedAt else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        currentURL = nil
        self.startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WKInterfaceDevice.current().play(.stop)

        guard duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        send(url, recordedAt: startedAt, duration: duration)
    }

    // MARK: Hand-off to iPhone

    private func send(_ url: URL, recordedAt: Date, duration: TimeInterval) {
        guard let session else {
            problem = "Can't reach iPhone"
            return
        }
        session.transferFile(url, metadata: [
            "id": url.deletingPathExtension().lastPathComponent,
            "recordedAt": recordedAt,
            "duration": duration
        ])
        refreshWaitingCount()
    }

    /// Queue any recording left on disk that the system is not already
    /// carrying (the app was killed, or an earlier transfer failed).
    private func requeueStranded() {
        guard let session, session.activationState == .activated else { return }
        let queued = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        for file in files where file.pathExtension == "m4a" && !queued.contains(file.lastPathComponent) {
            if file == currentURL { continue }
            let recordedAt = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            session.transferFile(file, metadata: [
                "id": file.deletingPathExtension().lastPathComponent,
                "recordedAt": recordedAt
            ])
        }
        refreshWaitingCount()
    }

    private func refreshWaitingCount() {
        waitingCount = session?.outstandingFileTransfers.count ?? 0
    }

    private func transferFinished(fileURL: URL, error: Error?) {
        if error == nil {
            // Only now is it safe to let go of the watch's copy.
            try? FileManager.default.removeItem(at: fileURL)
            lastSentAt = Date()
            problem = nil
        } else {
            problem = "Will retry sending to iPhone"
        }
        refreshWaitingCount()
    }
}

// MARK: - WCSessionDelegate

extension WatchRecorder: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated {
                self.requeueStranded()
            } else {
                self.problem = "Can't reach iPhone"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let fileURL = fileTransfer.file.fileURL
        Task { @MainActor in
            self.transferFinished(fileURL: fileURL, error: error)
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension WatchRecorder: AVAudioRecorderDelegate {
    /// The system ended the recording (a call, Siri). Send what was captured.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder, let url = self.currentURL, let startedAt = self.startedAt else { return }
            let duration = Date().timeIntervalSince(startedAt)
            self.recorder = nil
            self.currentURL = nil
            self.startedAt = nil
            if flag, duration >= Self.minimumDuration {
                self.send(url, recordedAt: startedAt, duration: duration)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
