# Letterly Feature Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add filler word removal, offline transcription retry queue, and audio file import to match Letterly's key features.

**Architecture:** (1) Filler removal is a GPT-4o-mini post-processing step after Whisper in `transcribeAndSave`. (2) Offline queue adds a `transcriptionStatus` field to Note and retry logic in `triggerAppActiveRefresh`. (3) Audio import adds a `.fileImporter` modifier to AIHomeView that feeds into the same transcription pipeline.

**Tech Stack:** SwiftUI, SwiftData, OpenAI API (Whisper + GPT-4o-mini), Network framework (NWPathMonitor), UniformTypeIdentifiers

---

### Task 1: Add filler word removal function to SummaryService

**Files:**
- Modify: `voice notes/SummaryService.swift`

- [ ] **Step 1: Add the cleanFillerWords function**

Add this static function to the `SummaryService` enum (after the existing `generateSummary` function, around line 165):

```swift
    // MARK: - Filler Word Removal

    static func cleanFillerWords(from transcript: String, apiKey: String) async throws -> String {
        // Skip very short transcripts
        guard transcript.split(separator: " ").count > 10 else {
            return transcript
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Remove filler words and verbal tics (um, uh, like, you know, so, basically, actually, I mean, right, sort of, kind of, well, yeah, okay so, honestly, literally) from this transcript. Preserve all meaning, tone, and sentence structure. Do not summarize, rephrase, or change the content. Return only the cleaned text."],
                ["role": "user", "content": transcript]
            ],
            "max_tokens": 4096,
            "temperature": 0.1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            // If parsing fails, return original transcript
            return transcript
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: add filler word removal function to SummaryService"
```

---

### Task 2: Wire filler removal into transcription pipeline

**Files:**
- Modify: `voice notes/AIHomeView.swift:779-801` (transcribeAndSave)

- [ ] **Step 1: Update transcribeAndSave to clean fillers after Whisper**

Replace the `transcribeAndSave` function (lines 779-801):

```swift
    private func transcribeAndSave(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil)
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                let rawTranscript = try await service.transcribe(audioURL: url)

                // Clean filler words (um, uh, like, you know, etc.)
                let transcript: String
                do {
                    transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
                } catch {
                    // If filler removal fails, use the raw transcript
                    transcript = rawTranscript
                }

                await MainActor.run {
                    saveNote(transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
```

Key change: Whisper output → `cleanFillerWords` → `saveNote`. If filler removal fails, falls back to raw transcript silently.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: wire filler word removal into transcription pipeline"
```

---

### Task 3: Add transcriptionStatus field to Note model

**Files:**
- Modify: `voice notes/Note.swift`

- [ ] **Step 1: Add the transcriptionStatus property**

After the `activeRewriteType` property (around line 136), add:

```swift
    // Transcription queue status
    var transcriptionStatus: String = "completed"  // "completed", "pending"
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/Note.swift"
git commit -m "feat: add transcriptionStatus field to Note model"
```

---

### Task 4: Save pending notes when transcription fails

**Files:**
- Modify: `voice notes/AIHomeView.swift:779-801` (transcribeAndSave — already modified in Task 2)

- [ ] **Step 1: Update the error path to save with pending status**

In the `transcribeAndSave` function, update the catch block. Replace:

```swift
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
```

with:

```swift
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil, pending: true)
                }
            }
```

- [ ] **Step 2: Update saveNote to accept pending parameter**

Find the `saveNote` function signature (around line 803):

```swift
    private func saveNote(transcript: String?) {
```

Replace with:

```swift
    private func saveNote(transcript: String?, pending: Bool = false) {
```

Then inside `saveNote`, right after `modelContext.insert(note)` and before `UsageService.shared.incrementNoteCount()`, add:

```swift
        if pending {
            note.transcriptionStatus = "pending"
        }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: save notes with pending status when transcription fails"
```

---

### Task 5: Add retry logic for pending transcriptions

**Files:**
- Modify: `voice notes/voice_notesApp.swift:184-232` (triggerAppActiveRefresh)

- [ ] **Step 1: Add pending transcription retry to triggerAppActiveRefresh**

At the end of the `triggerAppActiveRefresh` function (after the Tier 3 daily brief check, around line 232), add:

```swift
        // Retry pending transcriptions
        let pendingNotes = notes.filter { $0.transcriptionStatus == "pending" && $0.audioFileName != nil }
        if !pendingNotes.isEmpty, let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            for note in pendingNotes {
                guard let audioURL = note.audioURL else { continue }

                do {
                    let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                    let rawTranscript = try await service.transcribe(audioURL: audioURL)

                    // Clean filler words
                    let transcript: String
                    do {
                        transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
                    } catch {
                        transcript = rawTranscript
                    }

                    note.transcript = transcript
                    note.content = transcript
                    note.transcriptionStatus = "completed"
                    note.updatedAt = Date()
                    try? context.save()

                    // Run intelligence pipeline
                    let title = try? await SummaryService.generateTitle(for: transcript, apiKey: apiKey)
                    if let title = title {
                        note.title = title
                    }

                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: projects,
                        tags: (try? context.fetch(FetchDescriptor<Tag>())) ?? [],
                        context: context
                    )

                    // Update widget
                    SharedDefaults.updateLastNote(
                        preview: note.displayTitle,
                        date: note.updatedAt,
                        intent: note.intentType
                    )
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    // Still offline or API error — leave as pending, will retry next time
                    continue
                }
            }
        }
```

Note: This references `SummaryService.generateTitle` — check if it exists. If `generateTitle` is a private function in `AIHomeView` instead, we need to make it accessible. Let me check.

- [ ] **Step 2: Check if generateTitle is accessible**

The `generateTitle` function is in `AIHomeView` as a private function. For the retry logic in `voice_notesApp.swift`, we need a version accessible from outside. The simplest approach: add a static version to `SummaryService`.

Add to `SummaryService` (after `cleanFillerWords`):

```swift
    static func generateTitle(for text: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
                ["role": "user", "content": String(text.prefix(500))]
            ],
            "max_tokens": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return "Untitled Note"
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

Then update the retry code in Step 1 — the reference `SummaryService.generateTitle` now resolves.

- [ ] **Step 3: Add import for APIKeys if needed**

Check that `voice_notesApp.swift` can access `APIKeys`, `TranscriptionService`, `SummaryService`, `LanguageSettings`. These are all in the same target, so they should be accessible. No import needed.

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "voice notes/voice_notesApp.swift" "voice notes/SummaryService.swift"
git commit -m "feat: retry pending transcriptions when app becomes active"
```

---

### Task 6: Show pending indicator in notes list

**Files:**
- Modify: `voice notes/AIHomeView.swift` (the recent notes row)

- [ ] **Step 1: Find the AIRecentNoteRow and add pending indicator**

Search for `struct AIRecentNoteRow` in AIHomeView.swift. Add a pending indicator that shows when `note.transcriptionStatus == "pending"`.

Find where the note preview text is displayed in the row and wrap it with a condition:

```swift
if note.transcriptionStatus == "pending" {
    HStack(spacing: 4) {
        Image(systemName: "clock")
            .font(.caption2)
            .foregroundStyle(.orange)
        Text("Waiting to transcribe...")
            .font(.caption)
            .foregroundStyle(.orange)
    }
} else {
    // existing preview text
}
```

If `AIRecentNoteRow` is too complex to modify cleanly, an alternative is to add a small overlay/badge. The key requirement: the user must be able to see which notes are pending.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: show pending transcription indicator in notes list"
```

---

### Task 7: Add audio file import

**Files:**
- Modify: `voice notes/AIHomeView.swift` (add fileImporter + import button)
- Modify: `voice notes/HomeView.swift:1200-1246` (HomeBottomBar — add import button)

- [ ] **Step 1: Add import state and fileImporter to AIHomeView**

Add to the state variables section (around line 56, after `showingError`):

```swift
    @State private var showingAudioImporter = false
```

Add the `.fileImporter` modifier to the NavigationStack, near the other `.sheet` modifiers:

```swift
            .fileImporter(
                isPresented: $showingAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let sourceURL = urls.first else { return }
                    importAudioFile(from: sourceURL)
                case .failure(let error):
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
```

- [ ] **Step 2: Add the importAudioFile function**

Add this function near `transcribeAndSave`:

```swift
    private func importAudioFile(from sourceURL: URL) {
        // Start security-scoped access
        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file"
            showingError = true
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Copy to Documents directory with UUID filename
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = documentsPath.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            errorMessage = "Could not import file: \(error.localizedDescription)"
            showingError = true
            return
        }

        // Get audio duration
        if let player = try? AVAudioPlayer(contentsOf: destinationURL) {
            currentAudioFileName = fileName
            isTranscribing = true

            // Create note and transcribe
            transcribeAndSave(url: destinationURL)
        } else {
            errorMessage = "Could not read audio file"
            showingError = true
            // Clean up copied file
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }
```

- [ ] **Step 3: Add import button to HomeBottomBar**

In `HomeView.swift`, update the `HomeBottomBar` struct to accept an import callback and show the button.

Change the struct definition (line 1200-1203):

```swift
struct HomeBottomBar: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let onRecord: () -> Void
    var onTypeNote: (() -> Void)? = nil
    var onImportAudio: (() -> Void)? = nil
```

Replace the right-side spacer (line 1241-1242):

```swift
            // Balance spacer on right
            Color.clear.frame(width: 44, height: 44)
```

with:

```swift
            // Import audio button (right of record)
            if let onImport = onImportAudio, !isRecording && !isTranscribing {
                Button(action: onImport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .frame(width: 44, height: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
```

- [ ] **Step 4: Pass the import callback from AIHomeView**

In `AIHomeView.swift`, find where `HomeBottomBar` is used (around line 130):

```swift
                    HomeBottomBar(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        onRecord: toggleRecording
                    )
```

Update to:

```swift
                    HomeBottomBar(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        onRecord: toggleRecording,
                        onImportAudio: { showingAudioImporter = true }
                    )
```

- [ ] **Step 5: Add UniformTypeIdentifiers import**

At the top of `AIHomeView.swift`, add:

```swift
import UniformTypeIdentifiers
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add "voice notes/AIHomeView.swift" "voice notes/HomeView.swift"
git commit -m "feat: add audio file import from Files app"
```
