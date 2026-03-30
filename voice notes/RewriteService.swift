//
//  RewriteService.swift
//  voice notes
//
//  Rewrite/AI Improve service — Letterly-inspired rewrite templates
//

import Foundation

// MARK: - Rewrite Template

enum RewriteTemplateSection: String, CaseIterable, Identifiable {
    case favorites = "Favorites"
    case general = "General"
    case textEditing = "Text Editing"
    case summary = "Summary"
    case contentCreation = "Content Creation"

    var id: String { rawValue }
}

struct RewriteTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let section: RewriteTemplateSection
    let isPro: Bool
    let systemPrompt: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RewriteTemplate, rhs: RewriteTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Template Catalog

enum RewriteTemplateCatalog {
    static let magic = RewriteTemplate(
        id: "magic",
        name: "Enhance",
        emoji: "✨",
        section: .general,
        isPro: false,
        systemPrompt: "Rewrite this voice note into clear, well-structured prose. Expand on ideas, remove filler words, fix grammar, and make it read professionally while preserving the original meaning, intent, and voice. Keep a natural tone."
    )

    static let slightly = RewriteTemplate(
        id: "slightly",
        name: "Polish",
        emoji: "🪶",
        section: .general,
        isPro: true,
        systemPrompt: "Lightly touch up this voice note. Fix only obvious grammar mistakes, remove filler words (um, uh, like, you know), and clean up sentence flow. Make minimal changes — the output should sound almost identical to the original but polished."
    )

    static let significantly = RewriteTemplate(
        id: "significantly",
        name: "Expand",
        emoji: "🔭",
        section: .general,
        isPro: true,
        systemPrompt: "Substantially rewrite and expand this voice note. Improve clarity, add structure, expand on underdeveloped ideas, strengthen arguments, and produce a polished, comprehensive version. The meaning must be preserved but the writing quality should be dramatically improved."
    )

    static let structured = RewriteTemplate(
        id: "structured",
        name: "Organize",
        emoji: "📐",
        section: .textEditing,
        isPro: true,
        systemPrompt: "Rewrite this voice note into a well-structured document with clear headers, sections, and logical organization. Use markdown-style headers (##) to separate sections. Group related ideas together."
    )

    static let list = RewriteTemplate(
        id: "list",
        name: "Bullet Points",
        emoji: "📋",
        section: .textEditing,
        isPro: true,
        systemPrompt: "Convert this voice note into a clean, organized bullet point list. Group related items under headers if appropriate. Each bullet should be concise and actionable. Preserve all key information."
    )

    static let detailedSummary = RewriteTemplate(
        id: "detailed_summary",
        name: "Full Summary",
        emoji: "📄",
        section: .summary,
        isPro: true,
        systemPrompt: "Create a comprehensive summary of this voice note. Cover all key points, decisions, ideas, and action items mentioned. Organize into clear paragraphs. Nothing important should be omitted."
    )

    static let briefSummary = RewriteTemplate(
        id: "brief_summary",
        name: "Quick Take",
        emoji: "⚡",
        section: .summary,
        isPro: true,
        systemPrompt: "Summarize this voice note in 2-3 sentences. Capture only the most essential point(s). Be extremely concise."
    )

    static let email = RewriteTemplate(
        id: "email",
        name: "Email",
        emoji: "\u{2709}\u{FE0F}", // ✉️
        section: .contentCreation,
        isPro: true,
        systemPrompt: "Rewrite this voice note as a professional email. Include a subject line (on its own line prefixed with 'Subject:'), appropriate greeting, well-structured body paragraphs, and a professional sign-off. Keep the tone professional but warm."
    )

    static let linkedInPost = RewriteTemplate(
        id: "linkedin_post",
        name: "Professional Post",
        emoji: "💼",
        section: .contentCreation,
        isPro: true,
        systemPrompt: "Rewrite this voice note as an engaging LinkedIn post. Start with a compelling hook line, use short paragraphs, include relevant insights or lessons, and end with a question or call-to-action. Keep it concise and professional. Add 2-3 relevant hashtags at the end."
    )

    static let tweet = RewriteTemplate(
        id: "tweet",
        name: "Short Post",
        emoji: "💬",
        section: .contentCreation,
        isPro: true,
        systemPrompt: "Rewrite this voice note as a single short post (max 280 characters). Make it punchy, engaging, and shareable. Capture the core idea in the most compelling way possible."
    )

    // Favorites section shows enhance by default
    static let favoriteMagic = RewriteTemplate(
        id: "favorite_magic",
        name: "Enhance",
        emoji: "✨",
        section: .favorites,
        isPro: false,
        systemPrompt: magic.systemPrompt
    )

    static let allTemplates: [RewriteTemplate] = [
        favoriteMagic,
        magic, slightly, significantly,
        structured, list,
        detailedSummary, briefSummary,
        email, linkedInPost, tweet
    ]

    static func templates(for section: RewriteTemplateSection) -> [RewriteTemplate] {
        allTemplates.filter { $0.section == section }
    }
}

// MARK: - Rewrite Service

enum RewriteService {
    enum RewriteError: LocalizedError {
        case noAPIKey
        case noContent
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "OpenAI API key not configured"
            case .noContent: return "No content to rewrite"
            case .apiError(let msg): return "Rewrite failed: \(msg)"
            }
        }
    }

    /// Rewrite a transcript using a specific template
    static func rewrite(transcript: String, template: RewriteTemplate) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw RewriteError.noAPIKey
        }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RewriteError.noContent
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": template.systemPrompt],
                ["role": "user", "content": transcript]
            ],
            "max_tokens": 1500,
            "temperature": 0.4
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RewriteError.apiError(errorMsg)
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "No response generated"
    }
}
