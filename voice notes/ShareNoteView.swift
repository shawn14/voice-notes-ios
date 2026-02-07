//
//  ShareNoteView.swift
//  voice notes
//
//  UI for sharing a note via CloudKit
//

import SwiftUI
import CloudKit
import AVFoundation

struct ShareNoteView: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss

    @State private var isSharing = false
    @State private var sharedNote: SharedNote?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var expirationDays = 30
    @State private var includeAudio = true
    @State private var linkCopied = false

    private let expirationOptions = [7, 14, 30, 90]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let shared = sharedNote {
                    // Success state - show share link
                    SharedLinkView(
                        sharedNote: shared,
                        linkCopied: $linkCopied,
                        onDone: { dismiss() }
                    )
                } else {
                    // Configure share options
                    ShareOptionsView(
                        note: note,
                        expirationDays: $expirationDays,
                        includeAudio: $includeAudio,
                        expirationOptions: expirationOptions,
                        isSharing: isSharing,
                        onShare: shareNote
                    )
                }
            }
            .padding()
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Failed to share note")
            }
        }
    }

    private func shareNote() {
        isSharing = true

        Task {
            do {
                // Check CloudKit availability
                let status = try await CloudKitShareService.shared.checkAccountStatus()
                guard status == .available else {
                    throw ShareError.iCloudNotAvailable
                }

                // Upload to CloudKit
                let audioURL = includeAudio ? note.audioURL : nil
                let shared = try await CloudKitShareService.shared.shareNote(
                    title: note.title,
                    content: note.content,
                    audioFileURL: audioURL,
                    expiresIn: expirationDays
                )

                await MainActor.run {
                    sharedNote = shared
                    isSharing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSharing = false
                }
            }
        }
    }

    enum ShareError: LocalizedError {
        case iCloudNotAvailable

        var errorDescription: String? {
            switch self {
            case .iCloudNotAvailable:
                return "iCloud is not available. Please sign in to iCloud in Settings."
            }
        }
    }
}

// MARK: - Share Options View

struct ShareOptionsView: View {
    let note: Note
    @Binding var expirationDays: Int
    @Binding var includeAudio: Bool
    let expirationOptions: [Int]
    let isSharing: Bool
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.headline)
                    }

                    Text(note.content.prefix(200) + (note.content.count > 200 ? "..." : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if note.audioURL != nil {
                        HStack {
                            Image(systemName: "waveform")
                            Text("Audio attached")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            // Options
            VStack(alignment: .leading, spacing: 16) {
                Text("Options")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Include audio toggle
                if note.audioURL != nil {
                    Toggle(isOn: $includeAudio) {
                        Label("Include audio recording", systemImage: "waveform")
                    }
                }

                // Expiration picker
                HStack {
                    Label("Link expires in", systemImage: "clock")
                    Spacer()
                    Picker("Expires", selection: $expirationDays) {
                        ForEach(expirationOptions, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Spacer()

            // Share button
            Button(action: onShare) {
                HStack {
                    if isSharing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "link")
                    }
                    Text(isSharing ? "Creating link..." : "Create Share Link")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isSharing)

            // Info text
            Text("Recipients can view and listen. They'll need to download the app to create their own notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Shared Link View

struct SharedLinkView: View {
    let sharedNote: SharedNote
    @Binding var linkCopied: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Link Created!")
                .font(.title2.bold())

            // Link display
            VStack(spacing: 12) {
                Text(sharedNote.shareableURL.absoluteString)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        UIPasteboard.general.string = sharedNote.shareableURL.absoluteString
                        linkCopied = true

                        // Reset after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            linkCopied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                            Text(linkCopied ? "Copied!" : "Copy Link")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Share via system sheet
                    ShareLink(item: sharedNote.shareableURL) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let expiresAt = sharedNote.expiresAt {
                Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done", action: onDone)
                .font(.headline)
        }
    }
}

// MARK: - Shared Note Viewer (for recipients)

struct SharedNoteViewer: View {
    let shareID: String

    @State private var sharedNote: SharedNote?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading shared note...")
            } else if let note = sharedNote {
                SharedNoteContent(note: note)
            } else {
                ContentUnavailableView(
                    "Note Not Found",
                    systemImage: "doc.questionmark",
                    description: Text(errorMessage ?? "This note may have expired or been deleted.")
                )
            }
        }
        .task {
            await loadNote()
        }
    }

    private func loadNote() async {
        do {
            sharedNote = try await CloudKitShareService.shared.fetchSharedNote(id: shareID)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

struct SharedNoteContent: View {
    let note: SharedNote

    @State private var isPlayingAudio = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.title.bold())
                }

                // Audio player (if available)
                if let audioURL = note.audioURL {
                    SharedAudioPlayer(url: audioURL)
                }

                // Content
                Text(note.content)
                    .font(.body)

                // Metadata
                HStack {
                    Text("Shared \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    if let expires = note.expiresAt {
                        Text("• Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                // CTA to download app
                VStack(spacing: 12) {
                    Text("Want to create your own voice notes?")
                        .font(.headline)

                    Button {
                        // Link to App Store
                        // For now, just a placeholder
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.app")
                            Text("Get the App")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Shared Note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SharedAudioPlayer: View {
    let url: URL

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 12) {
            if let error = loadError {
                // Error state
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                HStack(spacing: 16) {
                    // Play/Pause button
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                    }

                    VStack(spacing: 8) {
                        // Progress slider
                        Slider(
                            value: Binding(
                                get: { currentTime },
                                set: { seek(to: $0) }
                            ),
                            in: 0...max(duration, 1)
                        )
                        .tint(.blue)

                        // Time labels
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(formatTime(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func setupPlayer() {
        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // Create player
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            loadError = "Unable to load audio"
            print("Audio player setup failed: \(error)")
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }

    private func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = player else { return }

            currentTime = player.currentTime

            // Check if playback finished
            if !player.isPlaying && isPlaying {
                isPlaying = false
                currentTime = 0
                player.currentTime = 0
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func stopPlayback() {
        player?.stop()
        stopTimer()
        isPlaying = false
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview("Share Options") {
    let note = Note(title: "Test Note", content: "This is a test note with some content.")
    return ShareNoteView(note: note)
}

#Preview("Shared Link") {
    let shared = SharedNote(
        id: "test-123",
        title: "My Voice Note",
        content: "Some content here",
        audioURL: nil,
        createdAt: Date(),
        expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
    )
    return SharedLinkView(
        sharedNote: shared,
        linkCopied: .constant(false),
        onDone: { }
    )
}
