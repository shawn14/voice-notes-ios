//
//  PersonaPreset.swift
//  voice notes
//
//  One-tap profession presets ("EEON Modes"). A preset is curated profile +
//  purpose text pushed through the SAME Tune EEON compile path as dictated
//  text — so the compiler shapes extraction, voice, and Ask context exactly
//  as it would for a user who described their job out loud. Presets are a
//  seed, not a cage: re-tuning by voice recompiles right over them.
//
//  Each preset also names the transform its notes should default to, which
//  drives the auto-summary on save (see PersonaPresetStore.defaultTransform).
//

import Foundation

struct PersonaPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let blurb: String
    let profileText: String
    let purposeText: String
    /// Raw value of the AITransformType this profession's notes default to.
    let defaultTransformRaw: String?

    static func == (lhs: PersonaPreset, rhs: PersonaPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum PersonaPresetCatalog {
    static let student = PersonaPreset(
        id: "student",
        name: "Student",
        icon: "graduationcap",
        blurb: "Lectures, readings, assignments",
        profileText: "I'm a student. I record lectures, study sessions, reading notes, and my own thinking as I work through material. My notes are full of concepts, terms, dates, formulas, and things professors flag as important.",
        purposeText: "Help me learn and keep up with coursework. From each note, pull out the key concepts and definitions, anything an instructor flagged as important or likely to be on an exam, assignments with their due dates, readings to complete, and questions I still need answered. Organize my notes by course and topic so I can study from them later.",
        defaultTransformRaw: "School Notes"
    )

    static let lawyer = PersonaPreset(
        id: "lawyer",
        name: "Lawyer",
        icon: "building.columns",
        blurb: "Matters, deadlines, case notes",
        profileText: "I'm an attorney. I dictate notes after client calls, hearings, depositions, and while working matters. My notes reference clients, opposing parties, matters, filings, citations, and deadlines.",
        purposeText: "Help me run my matters. From each note, capture which matter and parties it concerns, the key facts and issues discussed, positions and strategy, commitments I made and to whom, filing and statutory deadlines with their dates, and follow-up tasks. Preserve names, dates, dollar figures, and citations exactly as I said them — never paraphrase a citation or a number. Organize notes by matter and client.",
        defaultTransformRaw: "Case Note"
    )

    static let doctor = PersonaPreset(
        id: "doctor",
        name: "Doctor",
        icon: "stethoscope",
        blurb: "Encounters, findings, plans",
        profileText: "I'm a clinician. I dictate notes after patient encounters, rounds, and case discussions. My notes contain histories, exam findings, assessments, medications and dosages, and follow-up plans.",
        purposeText: "Help me keep clinical documentation straight. From each note, capture what was reported, objective findings I stated, my assessment, and the plan including follow-ups and referrals. Preserve every clinical detail, medication name, dosage, and figure exactly as dictated, and never infer a finding I did not state. Organize notes by patient case and topic.",
        defaultTransformRaw: "Clinical Note"
    )

    static let founder = PersonaPreset(
        id: "founder",
        name: "Founder / Builder",
        icon: "hammer",
        blurb: "Products, decisions, shipping",
        profileText: "I'm a founder building products. I talk through product decisions, customer conversations, technical tradeoffs, growth experiments, and what I'm shipping next.",
        purposeText: "Help me ship. From each note, capture the decision I made and its reasoning, what I committed to and by when, open questions blocking progress, customer signals worth acting on, and next steps with owners. Organize my notes by project and product area, and surface where I said one thing and did another.",
        defaultTransformRaw: "Executive Summary"
    )

    static let sales = PersonaPreset(
        id: "sales",
        name: "Sales",
        icon: "person.2",
        blurb: "Accounts, deals, follow-ups",
        profileText: "I work in sales. I record notes right after prospect and customer calls — what they need, who was on the call, objections raised, pricing discussed, and what happens next.",
        purposeText: "Help me work my pipeline. From each note, capture the account and people involved, the buyer's stated needs and pain, objections and how I handled them, pricing or terms discussed, next steps with dates, and anything I promised to send. Organize notes by account so I can prep for the next call in seconds.",
        defaultTransformRaw: "Meeting Minutes"
    )

    static let therapist = PersonaPreset(
        id: "therapist",
        name: "Therapist",
        icon: "heart.text.square",
        blurb: "Sessions, themes, follow-ups",
        profileText: "I'm a therapist. I dictate notes after client sessions — what the client brought in, themes I noticed, interventions I used, and what to follow up on next time.",
        purposeText: "Help me hold the thread between sessions. From each note, capture what the client presented, recurring themes and shifts over time, interventions used and their effect, risks or concerns to monitor, and what to revisit next session. Preserve my clinical language exactly; never invent an observation I didn't make. Organize notes by client.",
        defaultTransformRaw: "Clinical Note"
    )

    static let all: [PersonaPreset] = [founder, student, lawyer, doctor, sales, therapist]

    static func preset(id: String) -> PersonaPreset? {
        all.first { $0.id == id }
    }
}

/// Remembers which preset the user picked and which transform their notes
/// default to. Deliberately stored in UserDefaults rather than inside the
/// compiled persona schema: the preference must survive every LLM recompile
/// of the purpose article, and only the user (or a preset tap) should ever
/// change it.
enum PersonaPresetStore {
    private static let presetKey = "personaPresetId"
    private static let transformKey = "personaDefaultTransformRaw"
    static let autoSummarizeKey = "personaAutoSummarizeEnabled"

    static var selectedPresetId: String? {
        get { UserDefaults.standard.string(forKey: presetKey) }
        set { UserDefaults.standard.set(newValue, forKey: presetKey) }
    }

    static var selectedPreset: PersonaPreset? {
        guard let id = selectedPresetId else { return nil }
        return PersonaPresetCatalog.preset(id: id)
    }

    /// Raw value of the transform new notes are auto-summarized with.
    static var defaultTransformRaw: String? {
        get { UserDefaults.standard.string(forKey: transformKey) }
        set { UserDefaults.standard.set(newValue, forKey: transformKey) }
    }

    /// Auto-summarize is opt-in and costs an extra AI call per note.
    static var autoSummarizeEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoSummarizeKey)
    }

    static func apply(_ preset: PersonaPreset) {
        selectedPresetId = preset.id
        defaultTransformRaw = preset.defaultTransformRaw
    }
}
