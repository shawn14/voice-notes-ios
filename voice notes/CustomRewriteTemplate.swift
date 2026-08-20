//
//  CustomRewriteTemplate.swift
//  voice notes
//
//  User-authored post-capture transform. Bridged to RewriteTemplate at use
//  time so RewriteService and the picker UI stay schema-agnostic.
//

import Foundation
import SwiftData

@Model
final class CustomRewriteTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "✨"
    /// Compiled prompt the rewrite service consumes. Derived from
    /// globalInstructions + sections on save; kept as the single field the
    /// service reads so nothing downstream changes.
    var systemPrompt: String = ""

    /// Structured builder fields (2026-08-20). Overall goal, tone, and style
    /// for the whole template.
    var globalInstructions: String = ""

    /// JSON array of TemplateSection — the ordered sections the summary must
    /// contain, each with its own extraction instructions.
    var sectionsJSON: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(name: String, emoji: String = "✨", systemPrompt: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.systemPrompt = systemPrompt
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
    }

    /// Bridge to the value-type RewriteTemplate the picker + service consume.
    /// `custom_` id prefix prevents collision with built-in template ids.
    var asRewriteTemplate: RewriteTemplate {
        let safeEmoji = emoji.isEmpty ? "✨" : emoji
        return RewriteTemplate(
            id: "custom_\(id.uuidString)",
            name: name,
            emoji: safeEmoji,
            section: .favorites,
            isPro: false,
            systemPrompt: systemPrompt
        )
    }
}

/// One section of a structured template: a heading plus what to put under it.
struct TemplateSection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var instructions: String = ""
}

extension CustomRewriteTemplate {
    var sections: [TemplateSection] {
        get {
            guard let data = sectionsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([TemplateSection].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            sectionsJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    /// Build the prompt the AI actually receives from the structured fields.
    static func compilePrompt(globalInstructions: String, sections: [TemplateSection]) -> String {
        var parts: [String] = []
        let global = globalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty { parts.append(global) }

        let usable = sections.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !usable.isEmpty {
            var body = "Produce the note with exactly these sections, in this order. "
            body += "Use each section's heading verbatim as a bold label. Keep every "
            body += "fact, name, and number from the original — organize, never drop. "
            body += "If a section has nothing to report, say so in one short line "
            body += "rather than inventing content.\n"
            for section in usable {
                let instructions = section.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                body += "\n**\(section.title)** — \(instructions.isEmpty ? "what belongs under this heading" : instructions)"
            }
            parts.append(body)
        }
        return parts.joined(separator: "\n\n")
    }
}
