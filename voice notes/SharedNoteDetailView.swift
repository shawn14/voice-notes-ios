//
//  SharedNoteDetailView.swift
//  voice notes
//
//  Displays a shared note received via URL
//

import SwiftUI
import AVFoundation
import UIKit

struct SharedNoteDetailView: View {
    let sharedNote: SharedNote
    @Environment(\.dismiss) private var dismiss

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color("EEONBackground").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title
                        if !sharedNote.title.isEmpty {
                            Text(sharedNote.title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(Color("EEONTextPrimary"))
                        }

                        // Date
                        Text("Shared \(sharedNote.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(Color("EEONTextSecondary"))

                        // Expiration
                        if let expiresAt = sharedNote.expiresAt {
                            Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        // Content
                        Text(sharedNote.content)
                            .font(.body)
                            .foregroundStyle(Color("EEONTextPrimary").opacity(0.9))
                            .padding(.top, 8)

                        // Audio player
                        if sharedNote.audioURL != nil {
                            VStack(spacing: 16) {
                                Divider()
                                    .background(Color("EEONDivider"))

                                HStack {
                                    Button(action: togglePlayback) {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 48))
                                            .foregroundStyle(Color("EEONAccent"))
                                    }

                                    VStack(alignment: .leading) {
                                        Text("Audio Recording")
                                            .font(.headline)
                                            .foregroundStyle(Color("EEONTextPrimary"))
                                        Text("Tap to listen")
                                            .font(.caption)
                                            .foregroundStyle(Color("EEONTextSecondary"))
                                    }

                                    Spacer()
                                }
                            }
                            .padding(.top, 16)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding()
                }

                // CTA at bottom
                VStack {
                    Spacer()

                    VStack(spacing: 12) {
                        Text("Want to create your own voice notes?")
                            .font(.subheadline)
                            .foregroundStyle(Color("EEONTextSecondary"))

                        Button {
                            UIApplication.shared.open(SharedNote.appStoreURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.app.fill")
                                Text("Get EEON — Free")
                            }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color("EEONAccent"))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.clear, Color("EEONBackground")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    private func togglePlayback() {
        guard let audioURL = sharedNote.audioURL else { return }

        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else {
            do {
                // Set up audio session for playback
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)

                if audioPlayer == nil {
                    audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                    audioPlayer?.prepareToPlay()
                }
                audioPlayer?.play()
                isPlaying = true
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }
}
