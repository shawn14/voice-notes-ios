//
//  IngestSelfTest.swift
//  voice notes
//
//  DEBUG-only end-to-end proof for the in/out paths (2026-09-26). Launch with
//  `-SelfTestIngest <fixtures dir> <results.json>`: runs the REAL App Intents
//  (Add to EEON text + link, Add File PDF / photo / text file), lets the real
//  queue drain (OCR, PDF extraction, OpenAI extraction), then runs Get Recent,
//  Search and Ask and writes what came back to the results file. The
//  simulator can read and write host paths, so the caller reads the JSON.
//

#if DEBUG
import AppIntents
import Foundation
import SwiftData

enum IngestSelfTest {
    @MainActor
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-SelfTestIngest"), flag + 2 < args.count else { return }
        let fixtures = URL(fileURLWithPath: args[flag + 1])
        let output = URL(fileURLWithPath: args[flag + 2])
        Task { @MainActor in
            var report: [String: Any] = ["started": Date().description]
            do {
                var typed = AddToEEONIntent()
                typed.text = "Self test typed note: call the dentist Tuesday at 3pm about the crown."
                typed.noteTitle = "Shortcut typed note"
                _ = try await typed.perform()

                var link = AddToEEONIntent()
                link.text = "https://www.apple.com/newsroom/"
                link.noteTitle = "Shortcut link"
                _ = try await link.perform()

                for (file, title) in [("budget-review.pdf", "Shortcut PDF"),
                                      ("whiteboard.png", "Shortcut photo"),
                                      ("offsite-list.txt", "Shortcut text file")] {
                    var add = AddFileToEEONIntent()
                    add.file = IntentFile(fileURL: fixtures.appendingPathComponent(file), filename: file)
                    add.noteTitle = title
                    _ = try await add.perform()
                }

                // Wait for the queue to drain (each item is removed once saved).
                for _ in 0..<120 where !SharedDefaults.pendingIngests.isEmpty {
                    try await Task.sleep(for: .seconds(1))
                }
                report["queueLeft"] = SharedDefaults.pendingIngests.count

                let titles = ["Shortcut typed note", "Shortcut link", "Shortcut PDF", "Shortcut photo", "Shortcut text file"]
                let context = DataIntentBridge.container!.mainContext
                let all = try context.fetch(FetchDescriptor<Note>())
                report["notes"] = titles.map { title -> [String: Any] in
                    guard let note = all.first(where: { $0.title == title }) else { return ["title": title, "found": false] }
                    return ["title": title, "found": true, "source": note.sourceType.rawValue,
                            "content": String(note.content.prefix(160))]
                }

                var recent = GetRecentNotesIntent()
                recent.count = 5
                let recentResult = try await recent.perform()
                report["recentTitles"] = recentResult.value?.map(\.title) ?? []

                var search = SearchNotesIntent()
                search.query = "dentist crown"
                search.limit = 5
                report["searchTitles"] = try await search.perform().value?.map(\.title) ?? []

                var ask = AskEEONIntent()
                ask.question = "When do I need to call the dentist?"
                report["askAnswer"] = try await ask.perform().value ?? ""
            } catch {
                report["error"] = String(describing: error)
            }
            report["finished"] = Date().description
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output)
            }
        }
    }
}
#endif
