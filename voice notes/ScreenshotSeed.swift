//
//  ScreenshotSeed.swift
//  voice notes
//
//  Demo data seeder for App Store screenshot automation.
//
//  Triggered by the `-SeedScreenshotData` launch argument in DEBUG builds only.
//  Inserts a curated, realistic-looking founder persona with compiled
//  KnowledgeArticles, focus items, sample notes, and a pre-baked homeLayoutJSON
//  so the LLM compile loop is bypassed for screenshot capture.
//
//  Data is shaped to highlight EEON's unique value: voice-first capture +
//  AI-compiled knowledge layer + persona-tuned home + focus-driven momentum.
//

#if DEBUG
import Foundation
import SwiftData

enum ScreenshotSeed {

    /// Run the seed if the launch argument is present and the store is empty.
    /// Idempotent — only seeds on a fresh container.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-SeedScreenshotData") else { return }

        // Idempotency: skip if any non-seed notes exist
        let descriptor = FetchDescriptor<Note>()
        let existingNotes = (try? context.fetch(descriptor)) ?? []
        let nonSeedCount = existingNotes.filter { $0.sourceType != .profileSeed && $0.sourceType != .purposeSeed }.count
        if nonSeedCount > 5 { return }

        // Mark onboarding complete so the test launches into AIHomeView
        UserDefaults.standard.set(OnboardingState.completed.rawValue, forKey: "onboardingState")

        seedFounder(in: context)
    }

    // MARK: - Founder persona

    @MainActor
    private static func seedFounder(in context: ModelContext) {
        let now = Date()
        let cal = Calendar.current

        // ─── Profile + purpose seeds ────────────────────────────────
        let profile = Note(
            title: "Your Profile",
            content: "I'm Shawn — a founder running multiple AI-first companies. StockAlarm is my main focus right now. I capture meetings, ideas, half-baked product specs, and learnings as voice notes. I think out loud."
        )
        profile.sourceType = .profileSeed
        context.insert(profile)

        let purpose = Note(
            title: "Your Purpose",
            content: "I want EEON to organize my notes across all my businesses, surface where my momentum actually is, and call me out when I'm drifting from what I said matters most. Frame everything for execution readiness."
        )
        purpose.sourceType = .purposeSeed
        context.insert(purpose)

        // ─── .purpose KnowledgeArticle (the brain) ─────────────────────
        let purposeArticle = KnowledgeArticle(name: "Your Purpose", articleType: .purpose)
        purposeArticle.summary = "Founder/builder running multiple AI-first companies. Currently prioritizing StockAlarm as the main project, with EEON and Flash AI Cards in supporting roles."
        purposeArticle.thinkingEvolution = "The user is a founder shipping voice-first AI products. Frame responses to prioritize execution readiness, surface drift between stated focus and observed capture density, and lead with momentum over relationships."
        purposeArticle.voiceAndTone = "Direct, decision-oriented, terse. No throat-clearing. Imperative verbs. Short sentences. Numbers when they exist."
        purposeArticle.lastCompiledAt = cal.date(byAdding: .hour, value: -2, to: now)

        // Pre-baked home layout — knowledge + notes anchored at top, persona-shaped middle
        purposeArticle.homeLayoutJSON = """
        {"sections":[
          {"kindRaw":"knowledgeCarousel","title":"Knowledge","rationale":null,"limit":null,"staleDaysThreshold":null},
          {"kindRaw":"recentNotes","title":"Recent Notes","rationale":null,"limit":null,"staleDaysThreshold":null},
          {"kindRaw":"momentumPicture","title":"Where You Are","rationale":"Because you're a founder; observation beats prescription.","limit":null,"staleDaysThreshold":null},
          {"kindRaw":"priorityProjects","title":"Active Build","rationale":"Because you ship products; this surfaces what's moving.","limit":4,"staleDaysThreshold":null},
          {"kindRaw":"openDecisions","title":"Open Decisions","rationale":"Because unblocking decisions is how you keep velocity.","limit":4,"staleDaysThreshold":null},
          {"kindRaw":"ideaInbox","title":"Idea Inbox","rationale":"Because ideas land everywhere — capture before they leak.","limit":4,"staleDaysThreshold":null}
        ],"version":1}
        """

        // Focus items
        purposeArticle.focusItems = [
            FocusItem(content: "StockAlarm", weight: .primary, note: "where I want to spend most of my time"),
            FocusItem(content: "EEON", weight: .secondary, note: "voice-first AI memory app"),
            FocusItem(content: "Flash AI Cards", weight: .tertiary, note: nil)
        ]

        context.insert(purposeArticle)

        // ─── .index KnowledgeArticle (wiki overview) ───────────────────
        let indexArticle = KnowledgeArticle(name: "Your Wiki", articleType: .index)
        indexArticle.summary = "You're tracking 3 active projects (StockAlarm, EEON, Flash AI Cards), 8 people across investor and team contexts, and 4 emerging topics. StockAlarm dominates capture density this month; EEON has surged in the last week with the focus + momentum picture work."
        indexArticle.lastCompiledAt = cal.date(byAdding: .hour, value: -3, to: now)
        context.insert(indexArticle)

        // ─── .self KnowledgeArticle (about you) ────────────────────────
        let selfArticle = KnowledgeArticle(name: "You", articleType: .self)
        selfArticle.summary = "Founder building voice-first AI products. Shipped 8 versions of StockAlarm in 2026; co-founded EEON in early 2026 to compound voice notes into a personal knowledge graph."
        selfArticle.relationshipContext = "Direct communicator, builder identity, ships frequently, decision-oriented."
        selfArticle.thinkingEvolution = "Has shifted from breadth (multiple parallel projects) toward depth (StockAlarm as primary) over the last 30 days."
        selfArticle.lastCompiledAt = cal.date(byAdding: .hour, value: -5, to: now)
        selfArticle.mentionCount = 47
        context.insert(selfArticle)

        // ─── .project KnowledgeArticles ────────────────────────────────
        let stockAlarm = KnowledgeArticle(name: "StockAlarm", articleType: .project)
        stockAlarm.summary = "AI-powered stock alert and market intelligence platform. Streaming-data architecture is the current build focus. Recent decision to ship a paid tier in Q3."
        stockAlarm.openThreads = [
            OpenThread(thread: "Decide between WebSocket and SSE for live quotes", status: "open", daysOpen: 3),
            OpenThread(thread: "Pricing tier finalization with Patrick", status: "waiting", daysOpen: 5)
        ]
        stockAlarm.decisions = [
            ArticleDecision(decision: "Ship paid tier in Q3", status: "resolved", date: "2026-04-22"),
            ArticleDecision(decision: "Use Polygon.io for primary feed", status: "resolved", date: "2026-04-15")
        ]
        stockAlarm.sentimentArc = "Cautiously confident → Building momentum"
        stockAlarm.lastCompiledAt = cal.date(byAdding: .hour, value: -1, to: now)
        stockAlarm.mentionCount = 34
        stockAlarm.lastMentionedAt = cal.date(byAdding: .hour, value: -2, to: now)
        context.insert(stockAlarm)

        let eeonProject = KnowledgeArticle(name: "EEON", articleType: .project)
        eeonProject.summary = "Voice-first AI memory app. Just shipped 3.5.0 with focus + momentum picture, anchoring knowledge and notes at the top of the home. Tune EEON now lets users declare priorities as a structured list."
        eeonProject.openThreads = [
            OpenThread(thread: "Adaptive layout — should LLM rank content vs pick layout?", status: "open", daysOpen: 1),
            OpenThread(thread: "Reflection feature — bulk Q&A across notes", status: "open", daysOpen: 2)
        ]
        eeonProject.decisions = [
            ArticleDecision(decision: "Anchor knowledgeCarousel + recentNotes at home top", status: "resolved", date: "2026-05-08"),
            ArticleDecision(decision: "Strip founder-bias from homeLayoutJSON prompt", status: "resolved", date: "2026-05-07")
        ]
        eeonProject.sentimentArc = "Speculative → Concrete shipping cadence"
        eeonProject.lastCompiledAt = cal.date(byAdding: .hour, value: -1, to: now)
        eeonProject.mentionCount = 18
        eeonProject.lastMentionedAt = cal.date(byAdding: .hour, value: -1, to: now)
        context.insert(eeonProject)

        let flashCards = KnowledgeArticle(name: "Flash AI Cards", articleType: .project)
        flashCards.summary = "AI-powered flashcard study app. On hold — capture density has dropped to near-zero in the last 14 days as StockAlarm and EEON have absorbed attention."
        flashCards.openThreads = [
            OpenThread(thread: "Decide whether to revive Q4 or shelve", status: "stale", daysOpen: 14)
        ]
        flashCards.sentimentArc = "Hot launch → Quiet"
        flashCards.lastCompiledAt = cal.date(byAdding: .day, value: -10, to: now)
        flashCards.mentionCount = 7
        flashCards.lastMentionedAt = cal.date(byAdding: .day, value: -12, to: now)
        context.insert(flashCards)

        // ─── .topic KnowledgeArticles ──────────────────────────────────
        let aiMemory = KnowledgeArticle(name: "Voice-first AI memory architecture", articleType: .topic)
        aiMemory.summary = "Pattern: voice capture → embedding → vector search → LLM synthesis → compiled wiki. KnowledgeCompiler compiles topic articles from related notes. RAG retrieves at query time. ContextAssembler injects user persona into all AI calls."
        aiMemory.openThreads = [
            OpenThread(thread: "Map-reduce vs vector pre-filter for bulk reflection", status: "open", daysOpen: 1)
        ]
        aiMemory.thinkingEvolution = "Moved from per-note RAG toward compiled-article-first synthesis as the wiki grew."
        aiMemory.lastCompiledAt = cal.date(byAdding: .hour, value: -2, to: now)
        aiMemory.mentionCount = 24
        aiMemory.lastMentionedAt = cal.date(byAdding: .hour, value: -2, to: now)
        context.insert(aiMemory)

        // ─── .person KnowledgeArticles ────────────────────────────────
        let patrick = KnowledgeArticle(name: "Patrick Shannon", articleType: .person)
        patrick.summary = "Trader and StockAlarm power user. Interested in the streaming-data release. Met at the AI conference in March; has been the loudest external voice on pricing tier."
        patrick.relationshipContext = "Friendly trader, high-signal feedback. Engaged user."
        patrick.sentimentArc = "Neutral → Engaged"
        patrick.lastCompiledAt = cal.date(byAdding: .hour, value: -1, to: now)
        patrick.mentionCount = 12
        patrick.lastMentionedAt = cal.date(byAdding: .hour, value: -1, to: now)
        context.insert(patrick)

        let craig = KnowledgeArticle(name: "Craig", articleType: .person)
        craig.summary = "Engineering collaborator on the StockAlarm streaming pipeline. Came in via the AI dev community. Strong on backend infrastructure."
        craig.relationshipContext = "Technical contractor, collaborative."
        craig.sentimentArc = "Neutral → Collaborative"
        craig.lastCompiledAt = cal.date(byAdding: .day, value: -1, to: now)
        craig.mentionCount = 9
        craig.lastMentionedAt = cal.date(byAdding: .day, value: -1, to: now)
        context.insert(craig)

        let amber = KnowledgeArticle(name: "Amber", articleType: .person)
        amber.summary = "Personal contact — recurring dinner meet-ups, mostly social with occasional career talk."
        amber.sentimentArc = "Warm → Steady"
        amber.lastCompiledAt = cal.date(byAdding: .day, value: -3, to: now)
        amber.mentionCount = 5
        amber.lastMentionedAt = cal.date(byAdding: .day, value: -7, to: now)
        context.insert(amber)

        // ─── Notes ─────────────────────────────────────────────────────
        let notes: [(title: String, content: String, ago: TimeInterval, project: String?, intent: NoteIntent)] = [
            ("StockAlarm streaming decision", "Going with WebSocket for now — Polygon's SSE has too much retry noise. Patrick mentioned the same. Need to write the connection-pool config.", -3600, "StockAlarm", .decision),
            ("EEON adaptive layout idea", "What if knowledge and notes were anchored at the top universally? The persona-shaped middle gets reordered by signal density. Talked through this with the design swarm.", -7200, "EEON", .idea),
            ("Patrick — pricing tier feedback", "Patrick said $19/mo is fine for power traders, $9/mo is the right entry. Wants annual discount.", -14400, "StockAlarm", .update),
            ("Craig sync notes", "Craig's pulling the streaming infrastructure from his other project. Should be in main by Friday. Decision: pair on the integration, not async.", -86400, "StockAlarm", .decision),
            ("Voice-first design constraint", "Capture button MUST be at the bottom thumb zone, always reachable. Knowledge is the value layer; let users navigate into it from anywhere on home.", -10800, "EEON", .idea),
            ("Flash Cards revival?", "Should I bring Flash AI Cards back this quarter or shelve? Capture density has been near zero for 12 days. Probably shelve.", -129600, "Flash AI Cards", .decision),
            ("Reflection feature scoping", "User Q&A across all notes — should it use compiled article summaries (cheap) or raw notes (expensive)? Tier A: compiled. Tier C: map-reduce only when scope is huge.", -3600, "EEON", .idea),
            ("Daily 3", "1) Ship Mac Catalyst. 2) Review StockAlarm pricing with Patrick. 3) Decide on Flash AI Cards revival.", -1800, nil, .reminder)
        ]

        for (idx, n) in notes.enumerated() {
            let note = Note(title: n.title, content: n.content)
            note.transcript = n.content
            note.createdAt = now.addingTimeInterval(n.ago)
            note.updatedAt = note.createdAt
            note.intentType = n.intent.rawValue
            if let proj = n.project { note.inferredProjectName = proj }
            note.emotionalTone = ["confident", "decisive", "curious", "focused"][idx % 4]
            context.insert(note)
        }

        // ─── Today's 3 (DailyIntention) ───────────────────────────────
        let dateKey = ISO8601DateFormatter.localDateKey(for: now)
        let intentions = [
            DailyIntention(dateKey: dateKey, order: 0, content: "Ship Mac Catalyst 3.5.0 to TestFlight"),
            DailyIntention(dateKey: dateKey, order: 1, content: "Review StockAlarm pricing tier with Patrick"),
            DailyIntention(dateKey: dateKey, order: 2, content: "Decide on Flash AI Cards revival vs shelve")
        ]
        intentions.forEach { context.insert($0) }

        // ─── Sample extracted items ──────────────────────────────────
        let decisions = [
            ExtractedDecision(content: "Ship paid tier for StockAlarm in Q3", affects: "Revenue model", confidence: "High"),
            ExtractedDecision(content: "Anchor knowledge + notes at home top in EEON", affects: "Home UX", confidence: "High"),
            ExtractedDecision(content: "Pair with Craig on streaming integration", affects: "StockAlarm timeline", confidence: "Medium")
        ]
        decisions.forEach { context.insert($0) }

        let actions = [
            ExtractedAction(content: "Send Patrick the updated pricing deck", owner: "Me", deadline: "This week"),
            ExtractedAction(content: "Write streaming pool config for StockAlarm", owner: "Me", deadline: "Friday"),
            ExtractedAction(content: "Promote 3.5.0 to App Store after TestFlight feedback", owner: "Me", deadline: "Next Monday")
        ]
        actions.forEach { context.insert($0) }

        try? context.save()
    }
}

private extension ISO8601DateFormatter {
    static func localDateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}

#endif
