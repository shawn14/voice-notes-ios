//
//  NoteAdjustment.swift
//  voice notes
//
//  "Adjust" on the note: Shorter / Longer / Simpler / More formal. Unlike the
//  format chips — which always regenerate from the transcript so formats never
//  stack — an adjustment works on the text you are looking at and replaces it
//  in place, so Shorter twice keeps getting shorter. One level of undo lives
//  in NoteDetailView. Pocket calls this "adaptive summary editing" (Dec 2025).
//
//  Runs through RewriteService so the Tune EEON voice/tone directive applies;
//  the prompt states that the requested change wins over any style preference.
//

import Foundation

enum NoteAdjustment: String, CaseIterable, Identifiable {
    case shorter
    case longer
    case simpler
    case moreFormal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shorter: return "Shorter"
        case .longer: return "Longer"
        case .simpler: return "Simpler"
        case .moreFormal: return "More formal"
        }
    }

    var icon: String {
        switch self {
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .longer: return "arrow.up.left.and.arrow.down.right"
        case .simpler: return "text.badge.minus"
        case .moreFormal: return "briefcase"
        }
    }

    private var instruction: String {
        switch self {
        case .shorter:
            return "Make this about half as long. Keep every decision, name, number, date, and action item. Cut repetition, hedging, and examples first."
        case .longer:
            return "Expand this to roughly twice the length. Add connective explanation and context that is implied by the text; do not invent facts, names, numbers, or commitments that are not there."
        case .simpler:
            return "Rewrite this in plain language a newcomer would understand: short sentences, everyday words, one idea per sentence. Keep every fact, name, number, and action item."
        case .moreFormal:
            return "Rewrite this in a formal, professional register suitable for sending to a client or executive. No slang, no contractions, precise wording. Keep every fact, name, number, and action item."
        }
    }

    /// The rewrite template for this adjustment. `isPro` follows the catalog:
    /// everything beyond the baseline Enhance is Pro.
    var template: RewriteTemplate {
        RewriteTemplate(
            id: "adjust_" + rawValue,
            name: title,
            emoji: "",
            icon: icon,
            section: .textEditing,
            isPro: true,
            systemPrompt: "You are editing an existing note, not summarizing a transcript. "
                + instruction
                + " Preserve the existing structure (headings, bold labels, bullets) and the writer's voice. This instruction overrides any style preference given above. Return only the edited note."
        )
    }
}

// MARK: - Translate

/// "Translate" in the same menu. Works like an adjustment: it replaces the
/// text on screen and the one-level undo brings the original language back.
/// The transcript is never touched. A note too long to translate in one pass
/// fails with nothing changed (RewriteError.truncated), never half-translated.
enum NoteTranslationLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case portuguese = "Portuguese"
    case italian = "Italian"
    case chineseSimplified = "Chinese (Simplified)"
    case japanese = "Japanese"
    case korean = "Korean"
    case hindi = "Hindi"
    case arabic = "Arabic"
    case russian = "Russian"

    var id: String { rawValue }

    /// Long notes need room: a translation that stops mid-note is worse than
    /// none, so this asks for more output than the 1500-token rewrite default.
    static let maxTokens = 4000

    var template: RewriteTemplate {
        RewriteTemplate(
            id: "translate_" + rawValue,
            name: rawValue,
            emoji: "",
            icon: "character.bubble",
            section: .textEditing,
            isPro: true,
            systemPrompt: "You are translating an existing note, not summarizing it. Translate the whole note into "
                + rawValue
                + ". Translate every sentence; do not shorten, summarize, or add anything. Keep the structure exactly (headings, bold labels, bullets, numbering, line breaks). Keep company and product names, numbers, prices, and URLs exactly as written. If the note is already in "
                + rawValue
                + ", return it unchanged. This instruction overrides any style or language preference given above. Return only the translated note."
        )
    }
}
