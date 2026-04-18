//
//  ExportService.swift
//  voice notes
//
//  Generates a markdown export of all user data: notes (with transcripts,
//  extractions, tags) + compiled knowledge articles (person / project / topic
//  / self / purpose / reference). Returns a URL to a temp file ready for
//  ShareLink delivery.
//
//  Format: a single .md file with a JSON manifest at the top, then notes in
//  reverse-chronological order, then knowledge articles. Everything is
//  human-readable and portable to Obsidian / Notion / Logseq without
//  transformation.
//

import Foundation
import SwiftData

enum ExportService {
    /// Generate an export file and return the URL to write to.
    /// Heavy lifting (fetching + formatting) runs on a background actor;
    /// the final URL is returned on the caller's actor.
    @MainActor
    static func generateExport(context: ModelContext) throws -> URL {
        let allNotes = (try? context.fetch(FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []

        // Separate Tune EEON seeds from memory notes — they export to a dedicated
        // "Your EEON Profile" section at the top, not mixed into the note log.
        let profileSeed = allNotes.first { $0.sourceType == .profileSeed }
        let purposeSeed = allNotes.first { $0.sourceType == .purposeSeed }
        let notes = allNotes.filter { $0.sourceType != .profileSeed && $0.sourceType != .purposeSeed }

        let articles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>(
            sortBy: [SortDescriptor(\.articleTypeRaw), SortDescriptor(\.lastMentionedAt, order: .reverse)]
        ))) ?? []

        let decisions = (try? context.fetch(FetchDescriptor<ExtractedDecision>())) ?? []
        let actions = (try? context.fetch(FetchDescriptor<ExtractedAction>())) ?? []
        let commitments = (try? context.fetch(FetchDescriptor<ExtractedCommitment>())) ?? []

        // Index extractions by source note ID so we can inline them under each note
        let decisionsByNote = Dictionary(grouping: decisions, by: { $0.sourceNoteId ?? UUID() })
        let actionsByNote = Dictionary(grouping: actions, by: { $0.sourceNoteId ?? UUID() })
        let commitmentsByNote = Dictionary(grouping: commitments, by: { $0.sourceNoteId ?? UUID() })

        let markdown = buildMarkdown(
            profileSeed: profileSeed,
            purposeSeed: purposeSeed,
            notes: notes,
            articles: articles,
            decisionsByNote: decisionsByNote,
            actionsByNote: actionsByNote,
            commitmentsByNote: commitmentsByNote
        )

        let filename = "EEON-Export-\(timestampSlug()).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Markdown Assembly

    private static func buildMarkdown(
        profileSeed: Note?,
        purposeSeed: Note?,
        notes: [Note],
        articles: [KnowledgeArticle],
        decisionsByNote: [UUID: [ExtractedDecision]],
        actionsByNote: [UUID: [ExtractedAction]],
        commitmentsByNote: [UUID: [ExtractedCommitment]]
    ) -> String {
        var out = ""

        // Header
        let userName = AuthService.shared.userName ?? "EEON User"
        let exportDate = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        out += "# EEON Export — \(userName)\n"
        out += "Exported \(formatDisplayDate(exportDate)) · \(notes.count) note\(notes.count == 1 ? "" : "s") · \(articles.count) knowledge article\(articles.count == 1 ? "" : "s")\n\n"

        // JSON manifest (for tools that want to parse this)
        out += "```json\n"
        out += """
        {
          "app": "EEON",
          "version": "\(AppInfo.version)",
          "build": "\(AppInfo.build)",
          "exportedAt": "\(isoFormatter.string(from: exportDate))",
          "userName": \(jsonString(userName)),
          "noteCount": \(notes.count),
          "articleCount": \(articles.count)
        }
        """
        out += "\n```\n\n---\n\n"

        // Your EEON Profile (profile + purpose seeds, if set)
        if profileSeed != nil || purposeSeed != nil {
            out += "# Your EEON Profile\n\n"
            out += "*This is what you've told EEON about yourself — it shapes every AI response.*\n\n"
            if let profile = profileSeed, !profile.content.isEmpty {
                out += "## About You\n\n\(profile.content)\n\n"
            }
            if let purpose = purposeSeed, !purpose.content.isEmpty {
                out += "## What EEON Is For You\n\n\(purpose.content)\n\n"
            }
            out += "---\n\n"
        }

        // Notes
        out += "# Notes\n\n"
        if notes.isEmpty {
            out += "*(No notes yet.)*\n\n"
        } else {
            for note in notes {
                out += renderNote(
                    note,
                    decisions: decisionsByNote[note.id] ?? [],
                    actions: actionsByNote[note.id] ?? [],
                    commitments: commitmentsByNote[note.id] ?? []
                )
                out += "---\n\n"
            }
        }

        // Knowledge Articles
        out += "# Knowledge Articles\n\n"
        if articles.isEmpty {
            out += "*(No compiled knowledge articles yet.)*\n\n"
        } else {
            for article in articles {
                out += renderArticle(article)
                out += "---\n\n"
            }
        }

        out += "*Export complete.*\n"
        return out
    }

    private static func renderNote(
        _ note: Note,
        decisions: [ExtractedDecision],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment]
    ) -> String {
        var out = ""

        let intentTag = note.intentType.isEmpty ? "" : " · \(note.intentType)"
        let sourceTag: String
        switch note.sourceType {
        case .voice: sourceTag = ""
        case .webArticle: sourceTag = " · Web"
        case .derived: sourceTag = " · Derived"
        case .document: sourceTag = " · Document"
        case .audioImport: sourceTag = " · Audio Import"
        case .profileSeed: sourceTag = " · Profile Seed"
        case .purposeSeed: sourceTag = " · Purpose Seed"
        }

        out += "## \(formatDisplayDateTime(note.createdAt))\(intentTag)\(sourceTag)\n\n"

        if !note.title.isEmpty && note.title != note.displayTitle {
            out += "**Title:** \(note.title)\n\n"
        } else if !note.displayTitle.isEmpty {
            out += "**Title:** \(note.displayTitle)\n\n"
        }

        if let url = note.originalURL, !url.isEmpty {
            out += "**Source:** \(url)\n\n"
        }

        if let transcript = note.transcript, !transcript.isEmpty {
            out += "**Transcript:**\n\n\(transcript)\n\n"
        } else if !note.content.isEmpty {
            out += "**Content:**\n\n\(note.content)\n\n"
        }

        if let enhanced = note.enhancedNoteText, !enhanced.isEmpty, enhanced != note.transcript {
            out += "**Enhanced:**\n\n\(enhanced)\n\n"
        }

        if !decisions.isEmpty {
            out += "**Decisions:**\n"
            for d in decisions {
                let affects = d.affects.isEmpty ? "" : " *(affects: \(d.affects))*"
                out += "- \(d.content)\(affects)\n"
            }
            out += "\n"
        }

        if !actions.isEmpty {
            out += "**Actions:**\n"
            for a in actions {
                let owner = a.owner.isEmpty ? "me" : a.owner
                let deadline = a.deadline == "TBD" ? "" : " — \(a.deadline)"
                let done = a.isCompleted ? " ✓" : ""
                out += "- [\(owner)] \(a.content)\(deadline)\(done)\n"
            }
            out += "\n"
        }

        if !commitments.isEmpty {
            out += "**Commitments:**\n"
            for c in commitments {
                let done = c.isCompleted ? " ✓" : ""
                out += "- [\(c.who)] \(c.what)\(done)\n"
            }
            out += "\n"
        }

        if !note.mentionedPeople.isEmpty {
            out += "**People:** \(note.mentionedPeople.joined(separator: ", "))\n\n"
        }

        if !note.topics.isEmpty {
            out += "**Topics:** \(note.topics.joined(separator: ", "))\n\n"
        }

        if let tone = note.emotionalTone, !tone.isEmpty {
            out += "**Emotional tone:** \(tone)\n\n"
        }

        let tagNames = note.tags.map { $0.name }.filter { !$0.isEmpty }
        if !tagNames.isEmpty {
            out += "**Tags:** \(tagNames.map { "#\($0)" }.joined(separator: " "))\n\n"
        }

        if note.isFavorite { out += "*★ Favorited*\n\n" }
        if note.isArchived { out += "*📦 Archived*\n\n" }

        return out
    }

    private static func renderArticle(_ article: KnowledgeArticle) -> String {
        var out = ""

        let typeLabel = article.articleType.label
        out += "## [\(typeLabel)] \(article.name)\n\n"

        let lastSeen: String
        if let last = article.lastMentionedAt {
            lastSeen = " · last mentioned \(formatRelative(last))"
        } else {
            lastSeen = ""
        }
        out += "*\(article.mentionCount) mention\(article.mentionCount == 1 ? "" : "s")\(lastSeen)*\n\n"

        if !article.summary.isEmpty {
            out += "\(article.summary)\n\n"
        }

        if let rel = article.relationshipContext, !rel.isEmpty {
            out += "**Context:** \(rel)\n\n"
        }

        if let arc = article.sentimentArc, !arc.isEmpty {
            out += "**Sentiment arc:** \(arc)\n\n"
        }

        if let evolution = article.thinkingEvolution, !evolution.isEmpty {
            out += "**Evolution:** \(evolution)\n\n"
        }

        if !article.openThreads.isEmpty {
            out += "**Open threads:**\n"
            for t in article.openThreads {
                out += "- \(t.thread) *(\(t.status), \(t.daysOpen)d open)*\n"
            }
            out += "\n"
        }

        if !article.decisions.isEmpty {
            out += "**Decisions:**\n"
            for d in article.decisions {
                let dateTag = d.date.map { " — \($0)" } ?? ""
                out += "- \(d.decision) *(\(d.status))*\(dateTag)\n"
            }
            out += "\n"
        }

        if !article.timeline.isEmpty {
            out += "**Timeline:**\n"
            for e in article.timeline {
                out += "- \(e.date): \(e.event)\n"
            }
            out += "\n"
        }

        if !article.connections.isEmpty {
            out += "**Connections:**\n"
            for c in article.connections {
                out += "- \(c.articleName) — \(c.reason)\n"
            }
            out += "\n"
        }

        return out
    }

    // MARK: - Helpers

    private static func formatDisplayDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static func formatDisplayDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd · h:mm a"
        return f.string(from: date)
    }

    private static func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func timestampSlug() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /// Minimal JSON string escaping — enough for names/titles in the manifest.
    private static func jsonString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
