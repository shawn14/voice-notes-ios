//
//  AudioRecorder.swift
//  voice notes
//

import Foundation
import AVFoundation

@Observable
final class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?

    var isRecording = false
    var isPlaying = false
    var recordingTime: TimeInterval = 0
    var currentFileName: String?

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
        currentFileName = fileName
        recordingTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingTime += 1
        }

        return fileName
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        isRecording = false

        guard let fileName = currentFileName else { return nil }
        return getDocumentsDirectory().appendingPathComponent(fileName)
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
