//
//  ContextAssembler.swift
//  voice notes
//
//  Centralizes user-personalization context for AI calls.
//  Reads the user's .self and .purpose KnowledgeArticles (compiled by KnowledgeCompiler
//  from their profile/purpose seeds + voice notes) and exposes prefix strings to
//  inject into system / user messages.
//
//  Design: cached singleton, not a per-call SwiftData query.
//    - On app launch, voice_notesApp.init() calls refresh(from:) once.
//    - After each KnowledgeCompiler pass, recompileDirtyArticles() calls refresh(from:)
//      so the cache stays current with the latest .self / .purpose article content.
//    - AI call sites read synchronously with zero ModelContext coupling.
//
//  Replaces the scattered AuthService.eeonContextPrefix — kept only for migration fallback.
//

import Foundation
import SwiftData

enum AICallContext {
    case extraction     // Note intent/decision/action extraction
    case rag            // Q&A answering from user's memory
    case rewrite        // Enhanced note / transforms
    case dailyBrief     // Daily/weekly summary generation
    case analysis       // Report generation, article compile (purpose kept light here)
    case intent         // Intent classifier (note vs question) — neither injected
    case title          // Title generation — neither injected
    case tags           // Tag extraction — neither injected
    case fillerWords    // Filler-word cleanup — neither injected

    /// Whether this call site benefits from the user's purpose directive.
    var includesPurpose: Bool {
        switch self {
        case .extraction, .rag, .rewrite, .dailyBrief, .analysis: return true
        case .intent, .title, .tags, .fillerWords: return false
        }
    }

    /// Whether this call site benefits from the user's profile context.
    var includesProfile: Bool {
        switch self {
        case .extraction, .rag, .rewrite, .dailyBrief, .analysis: return true
        case .intent, .title, .tags, .fillerWords: return false
        }
    }

    /// Whether this call site benefits from the wiki index overview.
    /// Narrow on purpose: only Q&A and daily-brief synthesis benefit from "what's in the wiki".
    var includesIndex: Bool {
        switch self {
        case .rag, .dailyBrief: return true
        case .extraction, .rewrite, .analysis, .intent, .title, .tags, .fillerWords: return false
        }
    }

    /// Whether this call site benefits from the user's voice & tone directive.
    /// Narrow on purpose: only stylistic calls (rewrite + title). Analysis/extraction
    /// already get the heavier purposeDirective which subsumes voice for non-stylistic work.
    var includesVoiceAndTone: Bool {
        switch self {
        case .rewrite, .title: return true
        case .extraction, .rag, .dailyBrief, .analysis, .intent, .tags, .fillerWords: return false
        }
    }
}

struct AIContextPrefix {
    /// Inject into the system message (before the call's own system instructions).
    let system: String
    /// Inject at the start of the user message (before retrieval/content).
    let userPrefix: String

    static let empty = AIContextPrefix(system: "", userPrefix: "")

    var isEmpty: Bool { system.isEmpty && userPrefix.isEmpty }
}

@Observable
final class ContextAssembler {
    static let shared = ContextAssembler()

    /// The compiled "purpose directive" — injected into system prompts.
    private(set) var purposeDirective: String = ""
    /// The compiled "about the user" — injected into user messages.
    private(set) var profileContext: String = ""
    /// Wiki overview prose — injected into RAG / daily brief calls.
    private(set) var indexContext: String = ""
    /// Compiled voice & tone directive — injected into rewrite/title system prompts so
    /// stylistic output (formality, lyricism, vocabulary) matches the user's tuning.
    private(set) var voiceAndTone: String = ""

    private static let indexContextMaxChars = 400

    private init() {}

    /// Reload cached strings from SwiftData. Call on app launch + after each compile pass.
    @MainActor
    func refresh(from context: ModelContext) {
        purposeDirective = Self.loadPurposeDirective(in: context) ?? ""
        profileContext = Self.loadProfileContext(in: context) ?? ""
        indexContext = Self.loadIndexContext(in: context) ?? ""
        voiceAndTone = Self.loadVoiceAndTone(in: context) ?? ""
        print("[ContextAssembler] refreshed — purpose=\(String(purposeDirective.prefix(80))) profile=\(String(profileContext.prefix(60))) index=\(String(indexContext.prefix(60))) voice=\(String(voiceAndTone.prefix(60)))")
    }

    // MARK: - Static call-site API

    /// Build the personalization prefix for a given AI call site.
    /// Synchronous, zero SwiftData access — reads the cached strings.
    /// Falls back to legacy eeonContext if the .self article hasn't been compiled yet.
    static func prefix(for callContext: AICallContext) -> AIContextPrefix {
        let shared = ContextAssembler.shared

        var systemParts: [String] = []
        if callContext.includesPurpose && !shared.purposeDirective.isEmpty {
            systemParts.append(shared.purposeDirective)
        }
        if callContext.includesVoiceAndTone && !shared.voiceAndTone.isEmpty {
            systemParts.append(shared.voiceAndTone)
        }
        let system = systemParts.isEmpty ? "" : systemParts.joined(separator: "\n\n") + "\n\n"

        var userPrefixParts: [String] = []
        if callContext.includesProfile {
            if !shared.profileContext.isEmpty {
                userPrefixParts.append(shared.profileContext)
            } else {
                // Legacy fallback — pre-migration users
                let legacy = AuthService.shared.eeonContextPrefix
                if !legacy.isEmpty { userPrefixParts.append(legacy) }
            }
        }
        if callContext.includesIndex && !shared.indexContext.isEmpty {
            userPrefixParts.append(shared.indexContext)
        }

        let userPrefix = userPrefixParts.isEmpty ? "" : userPrefixParts.joined(separator: "\n\n") + "\n\n"

        return AIContextPrefix(system: system, userPrefix: userPrefix)
    }

    /// Convenience for call sites that don't split system / user prefixes.
    static func flatPrefix(for callContext: AICallContext) -> String {
        let p = prefix(for: callContext)
        return p.system + p.userPrefix
    }

    // MARK: - Article Loaders

    @MainActor
    private static func loadPurposeDirective(in context: ModelContext) -> String? {
        let purposeRaw = KnowledgeArticleType.purpose.rawValue
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == purposeRaw }
        )
        guard let article = (try? context.fetch(descriptor))?.first else { return nil }
        // Compiled directive lives in thinkingEvolution (see SummaryService.compileArticle for .purpose)
        if let directive = article.thinkingEvolution, !directive.isEmpty {
            return "User purpose directive:\n\(directive)"
        }
        if !article.summary.isEmpty {
            return "User purpose: \(article.summary)"
        }
        return nil
    }

    @MainActor
    private static func loadVoiceAndTone(in context: ModelContext) -> String? {
        let purposeRaw = KnowledgeArticleType.purpose.rawValue
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == purposeRaw }
        )
        guard let article = (try? context.fetch(descriptor))?.first,
              let voice = article.voiceAndTone, !voice.isEmpty else { return nil }
        return "Write in this voice & tone:\n\(voice)"
    }

    @MainActor
    private static func loadProfileContext(in context: ModelContext) -> String? {
        // Use hard-coded raw string — `KnowledgeArticleType.self` parses as the metatype.
        let selfRaw = "self"
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == selfRaw }
        )
        guard let article = (try? context.fetch(descriptor))?.first else { return nil }
        var parts: [String] = []
        if !article.summary.isEmpty {
            parts.append("About the user: \(article.summary)")
        }
        if let rel = article.relationshipContext, !rel.isEmpty {
            parts.append(rel)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    @MainActor
    private static func loadIndexContext(in context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == "index" }
        )
        guard let article = (try? context.fetch(descriptor))?.first,
              !article.summary.isEmpty else { return nil }
        let trimmed = String(article.summary.prefix(indexContextMaxChars))
        return "Wiki overview: \(trimmed)"
    }
}
