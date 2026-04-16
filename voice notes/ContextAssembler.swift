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

    private init() {}

    /// Reload cached strings from SwiftData. Call on app launch + after each compile pass.
    @MainActor
    func refresh(from context: ModelContext) {
        purposeDirective = Self.loadPurposeDirective(in: context) ?? ""
        profileContext = Self.loadProfileContext(in: context) ?? ""
        print("[ContextAssembler] refreshed — purpose=\(String(purposeDirective.prefix(80))) profile=\(String(profileContext.prefix(60)))")
    }

    // MARK: - Static call-site API

    /// Build the personalization prefix for a given AI call site.
    /// Synchronous, zero SwiftData access — reads the cached strings.
    /// Falls back to legacy eeonContext if the .self article hasn't been compiled yet.
    static func prefix(for callContext: AICallContext) -> AIContextPrefix {
        let shared = ContextAssembler.shared

        let system: String
        if callContext.includesPurpose && !shared.purposeDirective.isEmpty {
            system = shared.purposeDirective + "\n\n"
        } else {
            system = ""
        }

        let userPrefix: String
        if callContext.includesProfile {
            if !shared.profileContext.isEmpty {
                userPrefix = shared.profileContext + "\n\n"
            } else {
                // Legacy fallback — pre-migration users
                let legacy = AuthService.shared.eeonContextPrefix
                userPrefix = legacy.isEmpty ? "" : legacy
            }
        } else {
            userPrefix = ""
        }

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
}
