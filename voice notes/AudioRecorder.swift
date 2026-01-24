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

    private var timer: Timer?

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
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default)
        try audioSession.setActive(true)

        let fileName = "\(UUID().uuidString).m4a"
        let url = getDocumentsDirectory().appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
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
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)

        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.play()
        isPlaying = true
    }

    func stopPlaying() {
        audioPlayer?.stop()
        isPlaying = false
    }

    func deleteRecording(fileName: String) {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
