//
//  BackgroundDiarizationService.swift
//  voice notes
//
//  Runs Identify Speakers on a background URLSession so it survives the
//  user leaving EEON (2026-09-25). Measured live: a 24-min meeting takes
//  ~11 min end to end, and an in-app URLSession.shared request is
//  suspended ~30 s after the app backgrounds.
//
//  iOS owns uploads on a background session and relaunches EEON when each
//  finishes (`.backgroundTask(.urlSession(...))` in voice_notesApp). A
//  recording longer than one request is several sequential uploads, so each
//  job is a small JSON file in Application Support that says which chunk is
//  next and holds the segments and speaker references gathered so far.
//  Background sessions only upload from files, so each request body is
//  written to Caches first.
//

import Foundation
import SwiftData
import AVFoundation
import UserNotifications
import UIKit

@Observable
final class BackgroundDiarizationService: NSObject {
    static let shared = BackgroundDiarizationService()
    static let sessionIdentifier = "com.eeon.diarize"

    /// Notes with a job in flight (drives the "Listening for who said what…" row).
    private(set) var inFlight: Set<UUID> = []
    /// Last failure per note, shown once in the note and then cleared.
    /// Persisted: a failure that lands while the user is on another screen
    /// must still be there when they next open the note.
    private(set) var failures: [UUID: String] = [:] {
        didSet {
            UserDefaults.standard.set(
                Dictionary(uniqueKeysWithValues: failures.map { ($0.key.uuidString, $0.value) }),
                forKey: Self.failuresKey
            )
        }
    }
    private static let failuresKey = "diarizeFailures"
    /// Notes whose job is between steps in this process (starting, or handling
    /// a finished chunk). No upload task exists for them at that moment, so
    /// the startup sweep must not mistake them for interrupted jobs.
    @ObservationIgnored private var busy: Set<UUID> = []

    private var container: ModelContainer?
    @ObservationIgnored private var responseData: [Int: Data] = [:]
    @ObservationIgnored private var eventsFinished: CheckedContinuation<Void, Never>?
    /// iOS may suspend the app once the background-events handler returns, so
    /// it waits for completions that are still enqueueing the next chunk.
    @ObservationIgnored private var activeCompletions = 0
    @ObservationIgnored private var eventsDelivered = false
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 60 * 60 * 3
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private override init() { super.init() }

    /// Called once from voice_notesApp.init(); reconnects to uploads that
    /// were running when the app was last terminated.
    func configure(container: ModelContainer) {
        self.container = container
        let stored = UserDefaults.standard.dictionary(forKey: Self.failuresKey) as? [String: String] ?? [:]
        failures = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        // Snapshot BEFORE asking for tasks: only jobs that existed at launch
        // are candidates, never one started after this point.
        let atLaunch = Set(Job.all().map(\.noteID))
        inFlight = atLaunch
        // A force-quit cancels background uploads. A job whose upload no
        // longer exists would otherwise read "in flight" forever.
        session.getAllTasks { tasks in
            let live = Set(tasks.compactMap { $0.taskDescription?.split(separator: "|").first.map(String.init) })
            Task { @MainActor in
                for id in atLaunch where !live.contains(id.uuidString) && !self.busy.contains(id) {
                    guard let job = Job.load(id) else { continue }
                    self.fail(job, "Identify Speakers was interrupted. Run it again.")
                }
            }
        }
    }

    // MARK: - Job

    struct Reference: Codable { var name: String; var dataURL: String }

    struct Job: Codable {
        var noteID: UUID
        var audioFileName: String
        /// Transcript with any previous "Speaker X:" turns removed.
        var plainTranscript: String
        var duration: Double
        /// Start offsets in seconds; one upload per entry.
        var chunkStarts: [Double]
        var nextChunk: Int = 0
        var segments: [DiarizedSegment] = []
        var references: [Reference] = []

        static var directory: URL {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("diarize-jobs", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        var fileURL: URL { Self.directory.appendingPathComponent("\(noteID.uuidString).json") }

        static func load(_ id: UUID) -> Job? {
            let url = directory.appendingPathComponent("\(id.uuidString).json")
            return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Job.self, from: $0) }
        }
        static func all() -> [Job] {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(Job.self, from: $0) } }
        }
        func save() { try? JSONEncoder().encode(self).write(to: fileURL, options: .atomic) }
        func delete() { try? FileManager.default.removeItem(at: fileURL) }

        var audioURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(audioFileName)
        }
    }

    // MARK: - Start

    func isRunning(_ noteID: UUID) -> Bool { inFlight.contains(noteID) }

    func clearFailure(_ noteID: UUID) { failures[noteID] = nil }

    func start(note: Note) async throws {
        guard let fileName = note.audioFileName, let transcript = note.transcript else {
            throw SpeakerDiarizationService.DiarizationError.invalidAudio
        }
        guard !inFlight.contains(note.id) else { return }
        // Claim the note before the first await so a double tap is a no-op.
        inFlight.insert(note.id)
        busy.insert(note.id)
        defer { busy.remove(note.id) }
        let plain = transcript.replacingOccurrences(
            of: #"(?m)^Speaker [A-Z]: "#, with: "", options: .regularExpression
        ).replacingOccurrences(of: "\n\n", with: " ")

        var job = Job(noteID: note.id, audioFileName: fileName, plainTranscript: plain, duration: 0, chunkStarts: [])
        let duration = try? await AVURLAsset(url: job.audioURL).load(.duration)
        let seconds = duration.map(CMTimeGetSeconds) ?? 0
        guard seconds.isFinite, seconds > 0 else {
            inFlight.remove(note.id)
            throw SpeakerDiarizationService.DiarizationError.invalidAudio
        }
        job.duration = seconds
        job.chunkStarts = Self.chunkStarts(duration: seconds, audioURL: job.audioURL)

        failures[note.id] = nil
        job.save()
        do {
            try await enqueueNextChunk(of: job)
        } catch {
            fail(job, error.localizedDescription)
            throw error
        }
    }

    /// True when the original file can be sent as-is in one request.
    static func uploadsDirectly(duration: Double, audioURL: URL) -> Bool {
        let size = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        let direct = ["m4a", "mp3", "mp4", "wav", "webm", "ogg", "flac"].contains(audioURL.pathExtension.lowercased())
        return duration <= SpeakerDiarizationService.maxRequestSeconds
            && size <= SpeakerDiarizationService.maxUploadBytes && direct
    }

    static func chunkStarts(duration: Double, audioURL: URL) -> [Double] {
        if uploadsDirectly(duration: duration, audioURL: audioURL) { return [0] }
        var starts = Array(stride(from: 0, to: duration, by: SpeakerDiarizationService.chunkSeconds))
        // A sub-2-second tail is too short to diarize; fold it into the chunk
        // before (still well under the 1400 s request cap).
        if starts.count > 1, duration - starts[starts.count - 1] < 2 { starts.removeLast() }
        return starts
    }

    /// Writes the next chunk's request body to disk and hands it to iOS.
    private func enqueueNextChunk(of job: Job) async throws {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw SpeakerDiarizationService.DiarizationError.api("Speaker identification isn't available right now.")
        }
        let start = job.chunkStarts[job.nextChunk]
        // Decided by the file, not by the chunk count: a 15-min WAV over the
        // upload cap is one chunk that still has to be re-encoded.
        let direct = job.chunkStarts.count == 1 && Self.uploadsDirectly(duration: job.duration, audioURL: job.audioURL)
        let audio: URL
        if direct {
            audio = job.audioURL
        } else {
            let end = job.nextChunk + 1 < job.chunkStarts.count ? job.chunkStarts[job.nextChunk + 1] : job.duration
            audio = try await SpeakerDiarizationService.exportClip(from: job.audioURL, start: start, end: end)
        }
        defer { if !direct { try? FileManager.default.removeItem(at: audio) } }

        let boundary = UUID().uuidString
        let body = try SpeakerDiarizationService.multipartBody(
            fileURL: audio, references: job.references.map { ($0.name, $0.dataURL) }, boundary: boundary
        )
        let bodyURL = Self.bodyURL(for: job)
        try body.write(to: bodyURL, options: .atomic)

        let task = session.uploadTask(
            with: SpeakerDiarizationService.urlRequest(apiKey: apiKey, boundary: boundary),
            fromFile: bodyURL
        )
        task.taskDescription = "\(job.noteID.uuidString)|\(job.nextChunk)"
        task.resume()
    }

    private static func bodyURL(for job: Job) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diarize-\(job.noteID.uuidString)-\(job.nextChunk).body")
    }

    // MARK: - Completion

    private func handleCompletion(taskDescription: String?, statusCode: Int, data: Data, error: Error?) async {
        guard let parts = taskDescription?.split(separator: "|"), parts.count == 2,
              let noteID = UUID(uuidString: String(parts[0])), let chunk = Int(parts[1]),
              var job = Job.load(noteID), job.nextChunk == chunk else { return }
        busy.insert(noteID)
        defer { busy.remove(noteID) }
        try? FileManager.default.removeItem(at: Self.bodyURL(for: job))

        do {
            if let error { throw error }
            var segments = try SpeakerDiarizationService.parseSegments(data: data, statusCode: statusCode)
            let offset = job.chunkStarts[chunk]
            if job.chunkStarts.count > 1 {
                segments = SpeakerDiarizationService.relabel(
                    segments, known: Set(job.references.map(\.name)), used: Set(job.segments.map(\.speaker))
                )
            }
            for i in segments.indices {
                segments[i].start += offset
                segments[i].end += offset
            }
            job.segments += segments
            job.nextChunk += 1

            if job.nextChunk < job.chunkStarts.count {
                if job.references.count < SpeakerDiarizationService.maxReferences {
                    let new = try await SpeakerDiarizationService.newReferences(
                        for: segments, from: job.audioURL,
                        excluding: Set(job.references.map(\.name)),
                        limit: SpeakerDiarizationService.maxReferences - job.references.count
                    )
                    job.references += new.map { Reference(name: $0.name, dataURL: $0.dataURL) }
                }
                job.save()
                try await enqueueNextChunk(of: job)
            } else {
                try finish(job)
            }
        } catch {
            fail(job, error.localizedDescription)
        }
    }

    private func finish(_ job: Job) throws {
        guard let attributed = SpeakerAttribution.attributedTranscript(
            transcript: job.plainTranscript, segments: job.segments
        ) else {
            throw SpeakerDiarizationService.DiarizationError.singleSpeaker
        }
        guard let container else { throw SpeakerDiarizationService.DiarizationError.invalidAudio }
        let context = container.mainContext
        let noteID = job.noteID
        guard let note = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first else {
            job.delete()
            inFlight.remove(noteID)
            return
        }
        guard let merged = Self.resolveCompletedTranscript(
            current: note.transcript, startedFrom: job.plainTranscript, attributed: attributed
        ) else {
            throw SpeakerDiarizationService.DiarizationError.api(
                "This note's transcript changed while EEON was listening. Run Identify Speakers again."
            )
        }
        let previous = note.speakerLabels
        note.transcript = merged
        note.speakerLabels = SpeakerLabelDetector.markers(in: merged).map { marker in
            previous.first { $0.marker == marker } ?? SpeakerLabel(marker: marker, name: "")
        }
        try context.save()
        DocumentExportService.shared.export(note: note, context: context)

        job.delete()
        inFlight.remove(noteID)
        notify(noteID: noteID, title: note.title, body: "Speakers identified. Tap to name them.")
    }

    /// Decide what to write when a job finishes, given what the note says now.
    /// Returns nil to refuse the write (the user is told to run it again).
    static func resolveCompletedTranscript(current: String?, startedFrom: String, attributed: String) -> String? {
        guard let current else { return nil }
        // Compare the plain words, so a note that already carries speaker
        // turns from an earlier run still counts as unchanged.
        let currentPlain = current.replacingOccurrences(
            of: #"(?m)^Speaker [A-Z]: "#, with: "", options: .regularExpression
        ).replacingOccurrences(of: "\n\n", with: " ")
        return currentPlain == startedFrom ? attributed : nil
    }

    private func fail(_ job: Job, _ message: String) {
        job.delete()
        try? FileManager.default.removeItem(at: Self.bodyURL(for: job))
        inFlight.remove(job.noteID)
        failures[job.noteID] = message
        let noteID = job.noteID
        let title = (try? container?.mainContext.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })
        ).first?.title) ?? nil
        notify(noteID: noteID, title: title, body: "Couldn't identify speakers: \(message)")
    }

    /// Only notifies when the app is not in front; the note row shows it otherwise.
    private func notify(noteID: UUID, title: String?, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = (title?.isEmpty == false ? title : nil) ?? "EEON"
        content.body = body
        content.sound = .default
        content.userInfo["noteId"] = noteID.uuidString
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "diarize-\(noteID.uuidString)", content: content, trigger: nil)
        )
    }

    // MARK: - Background relaunch

    /// Called from `.backgroundTask(.urlSession(...))`. Reconnects the session
    /// and returns once iOS has delivered every pending event.
    func handleBackgroundEvents() async {
        // The session already exists (configure() runs at launch), so iOS may
        // deliver every event BEFORE this runs. eventsDelivered stays true in
        // that case and the continuation resumes immediately.
        await withCheckedContinuation { continuation in
            eventsFinished?.resume()
            eventsFinished = continuation
            _ = session
            resumeEventsIfIdle()
        }
    }

    private func resumeEventsIfIdle() {
        guard eventsDelivered, activeCompletions == 0, let continuation = eventsFinished else { return }
        eventsDelivered = false
        eventsFinished = nil
        continuation.resume()
    }
}

// Delegate callbacks arrive on `.main` (see `session`), so hopping onto the
// main actor with assumeIsolated is safe.
extension BackgroundDiarizationService: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        MainActor.assumeIsolated { responseData[id, default: Data()].append(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let description = task.taskDescription
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        MainActor.assumeIsolated {
            let data = responseData.removeValue(forKey: id) ?? Data()
            activeCompletions += 1
            Task {
                await handleCompletion(taskDescription: description, statusCode: status, data: data, error: error)
                activeCompletions -= 1
                resumeEventsIfIdle()
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            eventsDelivered = true
            resumeEventsIfIdle()
        }
    }
}
