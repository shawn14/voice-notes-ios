//
//  WhyThisHomeSheet.swift
//  voice notes
//
//  "Why does my home look like this?" — a transparency sheet.
//  Shows the user's purpose seed (what they said about themselves),
//  the compiled directive (what EEON internalized), and the list of
//  sections EEON picked for their home with per-section rationales.
//
//  Purpose: turn the LLM-compiled personalization from a black box into
//  a legible, editable artifact. Builds trust and retention.
//

import SwiftUI
import SwiftData

struct WhyThisHomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onTune: () -> Void

    @Query(filter: #Predicate<Note> { $0.sourceTypeRaw == "purposeSeed" })
    private var purposeSeedNotes: [Note]

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "purpose" })
    private var purposeArticles: [KnowledgeArticle]

    private var purposeText: String { purposeSeedNotes.first?.content ?? "" }
    private var directive: String {
        guard let article = purposeArticles.first else { return "" }
        if let t = article.thinkingEvolution, !t.isEmpty { return t }
        return article.summary
    }

    private var layout: HomeLayout {
        purposeArticles.first?.homeLayout ?? .default
    }

    private var sectionsWithRationale: [HomeSection] {
        // Only show sections that have a rationale (skip fallback layout sections without one)
        layout.sections.filter { $0.rationale?.isEmpty == false }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eeonBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        intro

                        if !purposeText.isEmpty {
                            section(title: "What you told EEON", icon: "quote.bubble", color: Color("EEONAccent")) {
                                Text(purposeText)
                                    .font(.body)
                                    .foregroundStyle(.eeonTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !directive.isEmpty {
                            section(title: "What EEON now understands", icon: "sparkles", color: .indigo) {
                                Text(directive)
                                    .font(.body)
                                    .foregroundStyle(.eeonTextPrimary.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !sectionsWithRationale.isEmpty {
                            section(title: "Why your home looks like this", icon: "rectangle.3.group", color: .orange) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(sectionsWithRationale) { s in
                                        sectionRow(for: s)
                                    }
                                }
                            }
                        }

                        tuneCTA
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Tuned for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Pieces

    private var intro: some View {
        Text("This is how EEON has shaped itself around what you've told it. Re-tune anytime to update.")
            .font(.subheadline)
            .foregroundStyle(.eeonTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.eeonTextSecondary)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    private func sectionRow(for section: HomeSection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.kind?.icon ?? "square.grid.2x2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("EEONAccent"))
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.effectiveTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                if let r = section.rationale {
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var tuneCTA: some View {
        Button {
            dismiss()
            // Small delay so the sheet dismissal doesn't collide with the next sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onTune()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                Text("Re-tune EEON")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color("EEONAccent"))
            .cornerRadius(14)
        }
    }
}

// MARK: - Kind Icon Helper

private extension HomeSectionKind {
    var icon: String {
        switch self {
        case .captureHero: return "mic.fill"
        case .priorityProjects: return "folder.fill"
        case .silentProjects: return "exclamationmark.triangle.fill"
        case .openDecisions: return "checkmark.seal"
        case .ideaInbox: return "lightbulb"
        case .todayThree: return "number.circle"
        case .openThreads: return "bubble.left.and.bubble.right"
        case .clientRoster: return "person.2.fill"
        case .followUpsPerClient: return "hand.raised.fill"
        case .relationshipArcs: return "heart.fill"
        case .recurringPatterns: return "sparkles"
        case .emotionalToneArc: return "waveform.path.ecg"
        case .referenceResonance: return "books.vertical.fill"
        case .activeInquiries: return "questionmark.circle"
        case .contradictionLedger: return "exclamationmark.octagon"
        case .knowledgeCarousel: return "square.grid.2x2"
        case .recentNotes: return "list.bullet"
        case .dailyBrief: return "sun.max"
        }
    }
}

#Preview {
    WhyThisHomeSheet(onTune: {})
        .modelContainer(for: [Note.self, KnowledgeArticle.self], inMemory: true)
}
