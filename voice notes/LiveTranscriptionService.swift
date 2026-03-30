//
//  LiveTranscriptionService.swift
//  voice notes
//
//  Real-time speech-to-text preview using Apple's Speech framework.
//  This is VISUAL FEEDBACK ONLY — the final transcription still uses Whisper.
//

import Foundation
import Speech
import AVFoundation

@Observable
final class LiveTranscriptionService {
    var liveTranscript: String = ""
    var currentWord: String = ""
    var isActive = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    /// Request authorization for speech recognition.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start live transcription using a separate audio engine tap.
    /// The AVAudioRecorder records to file independently; this taps the
    /// hardware input node for real-time recognition.
    func start() {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        liveTranscript = ""
        currentWord = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        // On-device recognition if available (faster, private)
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }
        recognitionRequest.shouldReportPartialResults = true

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let fullText = result.bestTranscription.formattedString
                // Extract the last word being spoken for highlight
                let words = fullText.components(separatedBy: " ")
                if result.isFinal {
                    self.liveTranscript = fullText
                    self.currentWord = ""
                } else {
                    // Everything except the last word is "confirmed"
                    if words.count > 1 {
                        self.liveTranscript = words.dropLast().joined(separator: " ")
                        self.currentWord = words.last ?? ""
                    } else {
                        self.liveTranscript = ""
                        self.currentWord = words.first ?? ""
                    }
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                // Don't tear down — the task may restart or finish naturally
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isActive = true
        } catch {
            print("LiveTranscription: audio engine failed to start — \(error)")
            stop()
        }
    }

    /// Stop live transcription and clean up.
    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isActive = false
    }
}
