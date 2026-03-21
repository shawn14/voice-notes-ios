//
//  PersonalizedReports.swift
//  voice notes
//
//  AI-generated report types tailored to the user's EEON context
//

import Foundation

struct PersonalizedReport: Codable, Identifiable {
    let id: String          // unique slug
    let name: String        // pill label (short, 1-2 words)
    let icon: String        // SF Symbol name
    let userPrompt: String  // what gets sent as the user message
    let instructions: String // system prompt instructions for this report
    let pillColor: String   // hex background
    let pillTextColor: String // hex text
}

// MARK: - Storage & Generation

enum PersonalizedReportStore {
    private static let storageKey = "personalizedReports"
    private static let contextHashKey = "personalizedReports.contextHash"

    /// Load cached personalized reports, or nil if none exist
    static var cached: [PersonalizedReport]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let reports = try? JSONDecoder().decode([PersonalizedReport].self, from: data),
              !reports.isEmpty else {
            return nil
        }
        return reports
    }

    /// Check if regeneration is needed (eeonContext changed since last generation)
    static var needsRegeneration: Bool {
        let currentHash = AuthService.shared.eeonContext?.hashValue ?? 0
        let storedHash = UserDefaults.standard.integer(forKey: contextHashKey)
        return currentHash != storedHash
    }

    /// Save generated reports to UserDefaults
    static func save(_ reports: [PersonalizedReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.set(AuthService.shared.eeonContext?.hashValue ?? 0, forKey: contextHashKey)
    }

    /// Clear cached reports (e.g. when eeonContext is cleared)
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: contextHashKey)
    }

    // MARK: - AI Generation

    /// Generate personalized report types from the user's EEON context.
    /// One API call, cached until context changes.
    static func generate() async throws -> [PersonalizedReport] {
        guard let ctx = AuthService.shared.eeonContext, !ctx.isEmpty,
              let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            return []
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let availableIcons = [
            "chart.bar.doc.horizontal", "arrow.up.arrow.down", "target", "calendar",
            "person.2", "folder", "checkmark.seal", "checklist", "dollarsign.circle",
            "fork.knife", "cart", "building.2", "hammer", "leaf", "heart.text.clipboard",
            "graduationcap", "paintbrush", "wrench.and.screwdriver", "globe",
            "megaphone", "lightbulb", "gauge.open.with.lines.needle.33percent",
            "chart.line.uptrend.xyaxis", "clock", "star", "flag", "bell",
            "doc.text", "list.bullet.clipboard", "arrow.triangle.branch"
        ]

        let colorPairs = [
            ("1a3a5c", "4a9eff"), ("3a1a1a", "ff6b6b"), ("1a3a1a", "4aff6b"),
            ("3a2a1a", "ffaa4a"), ("2a1a3a", "aa6bff"), ("1a2a3a", "4affff"),
            ("2a2a1a", "ffff4a"), ("1a2a2a", "4affaa")
        ]

        let systemPrompt = """
        You generate personalized report types for a voice notes app based on the user's profile.

        The user described themselves as:
        \(ctx)

        Generate 6-8 report types that would be most useful for THIS specific person.
        Each report should be relevant to their role, industry, and priorities.

        Available SF Symbol icon names (pick from this list ONLY):
        \(availableIcons.joined(separator: ", "))

        Return a JSON array with this EXACT structure:
        [
            {
                "id": "unique-slug",
                "name": "Short Label",
                "icon": "sf.symbol.name",
                "userPrompt": "What the user is asking for in plain language",
                "instructions": "Detailed markdown-structured instructions for the AI to generate this report, with ## section headers"
            }
        ]

        Rules:
        - name: 1-2 words max, fits in a pill button
        - id: lowercase kebab-case slug
        - icon: MUST be from the provided list above
        - userPrompt: 1 sentence, natural language
        - instructions: Include 3-5 ## sections with descriptions, tailored to the user's context
        - Always include a "Weekly" report type
        - Always include a "People" report type if they mention a team
        - Make reports actionable and specific to their domain
        - Return ONLY the JSON array, no other text
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt]
            ],
            "temperature": 0.4,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "PersonalizedReports", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw NSError(domain: "PersonalizedReports", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty response"])
        }

        // Parse the raw reports (without colors)
        struct RawReport: Codable {
            let id: String
            let name: String
            let icon: String
            let userPrompt: String
            let instructions: String
        }

        let rawReports = try JSONDecoder().decode([RawReport].self, from: jsonData)

        // Assign colors from the palette
        let reports = rawReports.enumerated().map { index, raw in
            let colorPair = colorPairs[index % colorPairs.count]
            return PersonalizedReport(
                id: raw.id,
                name: raw.name,
                icon: raw.icon,
                userPrompt: raw.userPrompt,
                instructions: raw.instructions,
                pillColor: colorPair.0,
                pillTextColor: colorPair.1
            )
        }

        save(reports)
        return reports
    }
}
