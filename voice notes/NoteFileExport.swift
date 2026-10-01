//
//  NoteFileExport.swift
//  voice notes
//
//  One note → a file other apps can take (2026-09-26): Markdown (Obsidian,
//  Notion, Bear, Drafts, GitHub), PDF (Mail, print, Files), or the original
//  recording renamed after the note. Before this every share path was plain
//  text or a link.
//

import Foundation
import UIKit

enum NoteFileExport {
    enum Format: String, CaseIterable, Identifiable {
        case markdown, pdf, recording
        var id: String { rawValue }
    }

    /// A temp file named after the note, ready for a share sheet.
    @MainActor
    static func file(for note: Note, format: Format, tasks: [ExtractedAction]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("note-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = safeFileName(note.displayTitle)

        switch format {
        case .markdown:
            let url = folder.appendingPathComponent("\(base).md")
            try markdown(for: note, tasks: tasks).write(to: url, atomically: true, encoding: .utf8)
            return url
        case .pdf:
            let url = folder.appendingPathComponent("\(base).pdf")
            try pdfData(html: html(for: note, tasks: tasks)).write(to: url, options: .atomic)
            return url
        case .recording:
            guard let source = note.audioURL, FileManager.default.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let url = folder.appendingPathComponent("\(base).\(ext)")
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: source, to: url)
            return url
        }
    }

    // MARK: Content

    struct Sections {
        var title: String
        var meta: [String]
        var body: String
        var tasks: [(done: Bool, text: String)]
        var transcript: String?
    }

    @MainActor
    static func sections(for note: Note, tasks: [ExtractedAction]) -> Sections {
        var meta = [note.createdAt.formatted(date: .long, time: .shortened)]
        if let meeting = note.calendarContext {
            var line = "Meeting: \(meeting.title)"
            if !meeting.attendees.isEmpty { line += " — \(meeting.attendees.joined(separator: ", "))" }
            meta.append(line)
        }
        if let link = note.originalURL, !link.isEmpty { meta.append("Source: \(link)") }

        let body = note.enhancedNoteText ?? note.transcript ?? note.content
        // Only include the transcript when it adds something beyond the body.
        var transcript: String?
        if let raw = note.transcript, !raw.isEmpty, raw != body {
            transcript = SpeakerAttribution.displayTranscript(raw, labels: note.speakerLabels)
        }
        let taskLines = tasks.map { (done: $0.isCompleted, text: $0.deadline == "TBD" ? $0.content : "\($0.content) (\($0.deadline))") }
        return Sections(title: note.displayTitle, meta: meta, body: body, tasks: taskLines, transcript: transcript)
    }

    @MainActor
    static func markdown(for note: Note, tasks: [ExtractedAction]) -> String {
        let s = sections(for: note, tasks: tasks)
        var out = "# \(s.title)\n\n" + s.meta.map { "_\($0)_" }.joined(separator: "  \n") + "\n\n" + s.body + "\n"
        if !s.tasks.isEmpty {
            out += "\n## Tasks\n\n" + s.tasks.map { "- [\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n") + "\n"
        }
        if let transcript = s.transcript {
            out += "\n## Transcript\n\n\(transcript)\n"
        }
        return out
    }

    @MainActor
    static func html(for note: Note, tasks: [ExtractedAction]) -> String {
        let s = sections(for: note, tasks: tasks)
        func esc(_ t: String) -> String {
            t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        func paragraphs(_ t: String) -> String {
            t.components(separatedBy: "\n\n").map { "<p>\(esc($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }.joined()
        }
        var out = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica; font-size: 12pt; line-height: 1.45; color: #1c1c1e; }
        h1 { font-size: 22pt; margin: 0 0 4pt; } h2 { font-size: 14pt; margin: 18pt 0 6pt; }
        .meta { color: #6e6e73; font-size: 10pt; margin-bottom: 14pt; } li { margin-bottom: 3pt; }
        </style></head><body>
        <h1>\(esc(s.title))</h1><div class="meta">\(s.meta.map(esc).joined(separator: "<br>"))</div>
        \(paragraphs(s.body.replacingOccurrences(of: "**", with: "")))
        """
        if !s.tasks.isEmpty {
            out += "<h2>Tasks</h2><ul>" + s.tasks.map { "<li>\($0.done ? "☑" : "☐") \(esc($0.text))</li>" }.joined() + "</ul>"
        }
        if let transcript = s.transcript {
            out += "<h2>Transcript</h2>" + paragraphs(transcript)
        }
        return out + "</body></html>"
    }

    /// US Letter with half-inch margins, paginated by UIKit's print system.
    @MainActor
    static func pdfData(html: String) -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 36, dy: 36), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func safeFileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "EEON Note" : String(cleaned.prefix(80))
    }
}
