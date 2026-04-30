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
    var systemPrompt: String = ""
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
