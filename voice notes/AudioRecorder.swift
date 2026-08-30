//
//  AudioRecorder.swift
//  voice notes
//

import Foundation
import AVFoundation
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit
#endif

/// Crash-safe marker for a recording in flight. Set when recording starts and
/// deliberately NOT cleared on stop — the note referencing the file is saved
/// well after stopRecording() returns, so clearing there leaves a crash window
/// with audio on disk and no marker. Launch recovery in voice_notesApp is the
/// only clearer: it clears once a note exists (or the file is gone) and
/// otherwise recovers the audio as a pending note.
enum InFlightRecordingMarker {
    private static let fileNameKey = "inflight_recording_fileName"

    static var fileName: String? {
        UserDefaults.standard.string(forKey: fileNameKey)
    }
    static func set(fileName: String) {
        UserDefaults.standard.set(fileName, forKey: fileNameKey)
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: fileNameKey)
    }
}

@Observable
final class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?

    /// True while ANY AudioRecorder instance is recording (all use is main-thread).
    /// BackgroundCaptureService checks this so an intent press can never start a
    /// second concurrent recorder over an in-app recording.
    static private(set) var isAnyRecording = false

    var isRecording = false
    var isPlaying = false
    var recordingTime: TimeInterval = 0
    var currentFileName: String?

    var isPaused = false
    private(set) var isManuallyPaused = false
    /// Fired on pause/resume so an owner (BackgroundCaptureService) can
    /// mirror the state into a Live Activity.
    var onPauseStateChange: ((Bool) -> Void)?

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var resumeRetryTask: Task<Void, Never>?

    // Playback control properties
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0

    private var timer: Timer?
    private var playbackTimer: Timer?

    override init() {
        super.init()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() throws -> String {
        #if !targetEnvironment(macCatalyst)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default)
        try audioSession.setActive(true)
        #endif

        let fileName = "\(UUID().uuidString).m4a"
        let url = getDocumentsDirectory().appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        isRecording = true
        AudioRecorder.isAnyRecording = true
        isManuallyPaused = false
        currentFileName = fileName
        InFlightRecordingMarker.set(fileName: fileName)
        installInterruptionObservers()
        recordingTime = 0

        // The screen is deliberately NOT pinned awake (2026-08-20). Recording
        // survives lock via the `audio` background mode and the Live Activity,
        // so holding the display on was pure battery cost on long captures.

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingTime += 1
        }

        return fileName
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        removeInterruptionObservers()
        resumeRetryTask?.cancel()
        resumeRetryTask = nil
        isPaused = false
        isManuallyPaused = false
        isRecording = false
        AudioRecorder.isAnyRecording = false

        setIdleTimerDisabled(false)

        guard let fileName = currentFileName else { return nil }
        return getDocumentsDirectory().appendingPathComponent(fileName)
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        if Thread.isMainThread {
            UIApplication.shared.isIdleTimerDisabled = disabled
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = disabled
            }
        }
        #endif
    }

    // MARK: - Interruption handling (calls, Siri, alarms, other apps' audio)
    //
    // Requirement: recording continues until the user stops it. Any
    // interruption pauses; resume is attempted unconditionally (not gated
    // on .shouldResume) and retried until the session frees or the user
    // stops. AVAudioRecorder.pause() keeps the file open, so record()
    // resumes appending to the same file.

    private func installInterruptionObservers() {
        removeInterruptionObservers()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            // A route change (BT mic dropped, etc.) can silently stop the
            // recorder. If we think we're recording but the recorder isn't,
            // treat it like an interruption and re-arm.
            guard let self, self.isRecording, !self.isPaused else { return }
            if self.audioRecorder?.isRecording == false {
                self.markPaused()
                self.attemptResume()
            }
        }
    }

    private func removeInterruptionObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        interruptionObserver = nil
        routeChangeObserver = nil
    }

    private func handleInterruption(_ notification: Notification) {
        guard isRecording else { return }
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            markPaused()
        case .ended:
            if !isManuallyPaused {
                attemptResume()
            }
        @unknown default:
            break
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        resumeRetryTask?.cancel()
        resumeRetryTask = nil
        isManuallyPaused = true
        pauseRecorder()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isManuallyPaused = false
        attemptResume()
    }

    private func markPaused() {
        guard isRecording, !isPaused else { return }
        pauseRecorder()
    }

    private func pauseRecorder() {
        audioRecorder?.pause()
        timer?.invalidate()
        timer = nil
        isPaused = true
        onPauseStateChange?(true)
    }

    private func attemptResume() {
        resumeRetryTask?.cancel()
        resumeRetryTask = Task { @MainActor [weak self] in
            while let self, self.isPaused, self.isRecording, !self.isManuallyPaused, !Task.isCancelled {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    if self.audioRecorder?.record() == true {
                        self.isPaused = false
                        self.restartTimer()
                        self.onPauseStateChange?(false)
                        return
                    }
                } catch {
                    // Session still owned by the interruptor (e.g. an active
                    // call). Keep retrying until it frees or the user stops.
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingTime += 1
        }
    }

    deinit {
        removeInterruptionObservers()
        resumeRetryTask?.cancel()
        // Safety net: if this recorder is torn down mid-recording, don't leave
        // the screen pinned awake forever.
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #endif
    }

    func playAudio(url: URL) throws {
        #if !targetEnvironment(macCatalyst)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        #endif

        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.enableRate = true
        audioPlayer?.rate = playbackRate
        audioPlayer?.play()
        isPlaying = true
        duration = audioPlayer?.duration ?? 0

        // Start playback timer for current time tracking
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }

    func stopPlaying() {
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        currentTime = 0
    }

    func pausePlaying() {
        audioPlayer?.pause()
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
    }

    func resumePlaying() {
        audioPlayer?.play()
        isPlaying = true

        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = min(max(0, time), player.duration)
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer?.rate = rate
    }

    func deleteRecording(fileName: String) {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Returns the current average power in decibels (-160 silence … 0 max).
    /// Call from a display-link / timer to drive waveform UI.
    var currentLevel: Float {
        guard let recorder = audioRecorder, recorder.isRecording else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    /// Normalized 0…1 value suitable for driving UI (maps -50 dB … 0 dB → 0…1).
    var normalizedLevel: CGFloat {
        let level = currentLevel
        let minDb: Float = -50
        let clamped = max(minDb, min(level, 0))
        return CGFloat((clamped - minDb) / (0 - minDb))
    }

    /// The URL of the file currently being recorded, for use by live transcription tap.
    var currentRecordingURL: URL? {
        guard let fileName = currentFileName else { return nil }
        return getDocumentsDirectory().appendingPathComponent(fileName)
    }

    var recordingStatusText: String {
        if isPaused {
            return isManuallyPaused ? "Paused" : "Paused · auto-resumes"
        }
        return "Recording"
    }

    var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        currentTime = 0
    }
}
