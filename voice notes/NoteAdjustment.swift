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
