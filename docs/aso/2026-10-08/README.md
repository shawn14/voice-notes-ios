# EEON ASO research and release draft — 2026-10-08

Decision: test **brain dumps that preserve decisions and follow-ups**. Audience: people who think out loud and want useful recall, rather than a meeting transcription service. Primary promise: **Talk it through. Keep the tasks. Remember the decision.** This is a positioning experiment, not a proven untaken market. The research found no defensible vacant category with demonstrated demand. Do not claim exclusivity or forecast downloads from these results.

Status: complete local research and validated metadata draft; not uploaded. Public EEON is3.9.0;3.10.0(171) is WAITING_FOR_REVIEW. Preserve that submission. ASO publication requires Shawn's explicit approval and an editable Apple version. Do not cancel its review merely to change copy.

## Observed baseline

Apple public lookup today: EEON: AI Memory & Notes, Productivity, free download,2 US ratings,5.0 average. This is a small credibility base, not proof of conversion quality. Actual ASC name/subtitle agree with local Fastlane metadata: name EEON: AI Memory & Notes; subtitle Voice notes, tasks & recall. Current keywords already include brain dump, decisions and commitments; the experiment promotes brain dump into the subtitle and aligns conversion copy around a concrete result. Simply adding the keyword again would change nothing.

The first existing screenshot leads with Your personal AI assistant / Say it once. EEON remembers. It shows calendar setup and a broad home screen, rather than proving the brain-dump transformation. The second screenshot is calendar. Recommended conversion change: show the useful note first, its follow-up tasks second, and recall third. Calendar is supporting context.

Exact baseline: evidence/current-listing.json. No App Analytics impressions, first-time downloads, conversion, retention or source-country breakdown was retrieved; public rating counts do not substitute for these. No claim that ASO is the only cause of low downloads.

## Market evidence

AppleCharts live US searches, six-month review window,8 analyzed apps per query. Detailed listings, review examples and coverage are saved in evidence/applecharts.json. Result ordering is Apple's public search endpoint, not a verified personalized iPhone organic rank. Reviews and apps overlap across queries; do not sum them into unique users.

| Query | Search results | Reviews in window | Important observed competitors | Assessment |
|---|---:|---:|---|---|
| voice notes |21|784|Apple Voice Memos1,103,899 ratings; TapMedia453,070; Otter83,750; Voicenotes7,081|Crowded, broad category already won by well-established apps|
| brain dump |25|262|Brain Dump: AI Notes & Writing64; Jot45; MinimaList48,130|Smaller specialist brands, but14/25 results target the phrase; contested, not empty|
| ADHD voice notes |23|288|Claireti0; Brain Dump: ADHD Voice Notes0; Numo1,071|Explicit specialists already exist; no clinical positioning for EEON|
| voice to reminders |25|207|AiRemindr1; AI Reminder0; Todoist129,584|Literal title matching says open but first-party sites prove occupied functionality|
| decision journal |25|0|22/25 titles target decision journals; eight analyzed leaders total4 ratings|Supply without useful recent review evidence; absence of reviews is not demand|
| client notes |24|82|Client Note Tracker103; Clients413; Contacts Journal2,447|Existing CRM intent; EEON lacks the corresponding client-management workflow|
| voice follow up |24|98|Mostly voice changers/coaches|Irrelevant results, not validated search demand|
| meeting debrief |22|97|Debrief AI Meeting Coach0; Echo3,670; Calendly55,360|Mixed intent, competitors exist; weak basis for primary ASO|

Reproduce any query with AppleCharts keyword_roadmap(keyword,months=6,country=us,format=json), or its local pnpm roadmap CLI. Human links: [voice notes](https://www.applecharts.com/roadmap/?q=voice%20notes&months=6), [brain dump](https://www.applecharts.com/roadmap/?q=brain%20dump&months=6).

### First-party refutations of attractive claims

- [WhisperAct](https://whisperact.com/) already routes spoken tasks/events into Apple Reminders/Calendar. [Voctara](https://voctara.com/) and [Offload](https://offload-app.pages.dev/) also target this handoff. Apple-native tasks alone are not an untaken wedge.
- [Murble](https://getmurble.com/) offers transcription, tasks, Reminders sync and note questions with on-device processing. EEON uses cloud AI; do not claim offline/private AI processing or market-wide superior privacy.
- [Granola MCP](https://www.granola.ai/blog/granola-mcp) already connects meeting memory to external AI tools. The existing EEON agent connector is a supporting benefit, not exclusive differentiation.
- [Sidenotes](https://sidenotes.app/articles/voice-note-debrief-after-coaching-sessions), [Alter](https://youalter.com/contacts/blog/voice-notes-after-client-meetings) and [TalkRecap](https://www.talkrecap.com/for/freelancers) already market post-client debriefs. This is not a vacant vertical.
- [Nod](https://hellonod.app/) and [Selv](https://www.selv.io/) target working memory and commitments. Broad remember-what-you-promised positioning is also occupied.

- Independent fresh-context refuter also found [Audionotes](https://www.audionotes.app/) explicitly selling brain dumps into actionable notes, with [ADHD workflows](https://www.audionotes.app/usecase/adhd) and searchable follow-ups. [Voicenotes](https://voicenotes.com/) already offers decision recall and its [MCP use case](https://voicenotes.com/blog/usecase/voicenotes-mcp/) combines walk ideas, client follow-ups and AI access. Thus even the exact combined brain-dump promise is occupied. Subtitle is a relevance/conversion hypothesis, not a demonstrated unique category. A personal debrief variant can be tested later, but Sidenotes/Alter already prevent claiming that is empty.

Why this experiment anyway: compared with broad voice notes, brain dump has smaller named specialist incumbents. EEON already has note enhancement, decisions/actions extraction and archive questions, so it can show a complete useful loop without a new feature build. The opportunity is a clearer result and narrower audience, not inventing a new category. Willingness to pay and query volume remain unknown.

### Review interpretation and tool limitations

Voice-notes report classified45 pricing and17 reliability complaints. These are machine tags, not audited complaint counts: some positive reviews were mislabeled, and singing reviews appeared under coaching. Brain-dump samples mostly reflect MinimaList rather than voice-capture customers. Manually inspected examples show pricing friction and lost-recording concerns but do not prove unmet demand for EEON's precise combined promise. Existing Otter review14577265824 praises sorting ideas for clarity; Voicenotes review14565365333 describes journaling/brainstorming use. These support the thinking-aloud use case, not uniqueness.

Autocomplete-based demandScore is relative hint order, not search volume. Nearby suggestions include competitors' branded names. Do not target those names, treat modeled revenue/downloads as facts, or trust an open verdict based on literal title matching. AppleCharts says voice-to-reminders has0 title matchers despite AiRemindr — a useful counterexample to its matching heuristic.

## Core three outcomes and claim boundaries

1. **Get a messy thought into a readable note.** Existing shipped extraction/enhancement pipeline; original transcript preserved. Screenshot must show actual current app output. Defer dictation keyboard, which is a locked separate-product decision.
2. **Keep the follow-ups where they will be used.** Existing actions extraction and opt-in EventKitSyncService, sourceNoteId deduplication, task completion. Say enable/connect Reminders; do not imply it is on without permission. Physical sync for this new marketing fixture must be verified before using its result screenshot.
3. **Find what you decided later.** Existing RAGService questions across notes and extracted decisions. Do not promise perfect recall, guaranteed exhaustive answers or proactive follow-up execution. AI output accuracy is probabilistic.

Checked against exact submitted source tag appstore/voice-notes/3.10.0-build171, not only newer main. Watch, Translate, transcript editing and tap-to-hear are unverified main-only work and excluded from this pack. No new product feature, pricing or entitlement change is proposed.

## Metadata draft

Files: metadata/en-US/. Validated lengths: name23/30; subtitle27/30; keywords93/100; promotional text165/170; description2057/4000.

Name: **EEON: AI Memory & Notes** — retained per existing-name rule.

Subtitle: **Brain dumps, tasks & recall**

Keywords: `voice,journal,dictation,transcribe,meeting,reminders,decisions,commitments,thoughts,follow up`

Keywords cover the capture category plus task/decision outcomes without repeating name/subtitle words. No competitor brands, ADHD claim, clinical claim, irrelevant high-volume terms or price change. Full description is benefit-led with optional Reminders, cloud-AI disclosure and subscription disclosure. Promotional text serves conversion; it does not improve search ranking. Release notes are copied unchanged from3.10.0, not invented for a copy-only change; update for the actual next release if its behavior differs.

Sources: [Apple search rules](https://developer.apple.com/app-store/search/), [product page guidance](https://developer.apple.com/app-store/product-page/).

## Screenshot release plan

Use real captures from the shipped build; do not paint hypothetical app UI or repurpose old captures as current proof. Existing Sep1 captures are useful references, not sufficient evidence for new screenshot publication. Keep example content visibly labeled Example in the frame. Capture one coherent fixture: “We decided to launch Friday. I need to send Lena the pricing deck tomorrow. The onboarding idea is a shorter first screen.” Verify exact output before framing it.

| Order | Hook | Screen/result to capture | Evidence and purpose |
|---|---|---|---|
|1|Turn a brain dump into a clear note|Actual enhanced note with the example launch thought; original accessible|Category specialist opportunity; outcome visible immediately|
|2|Keep the follow-ups|Tasks extracted from that note; clear source context|Show actions, not a vague AI claim|
|3|Remember what you decided|Ask EEON about the launch; actual sourced answer|Differentiate the full loop from a one-off transcript|
|4|Use Apple Reminders|Actual permission-enabled EEON list with the verified action|Useful integration already offered by competitors; proof, not exclusivity|
|5|Speak when an idea arrives|Current recording screen/entry point on iPhone/iPad|Supports frictionless capture without advertising unshipped Watch|

No final replacement screenshots generated or uploaded yet. Existing compose_screenshots.py can frame verified raw captures; use an isolated output directory so production assets are not overwritten before approval.

## Measurement and publication

1. Before publishing, export the previous28 complete days of US iPhone App Store Search impressions, first-time downloads and conversion from App Analytics, separated from Apple Ads if available. Also record App Store Browse and referral downloads. Save the export here. Two ratings cannot establish downloads or a conversion baseline.
2. Publish one coherent default-page treatment: subtitle/keyword/description plus matching first three screenshot outcomes. Keep name, price, paywall and acquisition spend stable. This is a sequential metadata test, not a randomized title/keyword experiment. Apple Product Page Optimization can test eligible screenshots/icons/previews; it does not randomize name/subtitle/keywords.
3. Observe28 complete days with weekly checks. Report absolute counts and source mix, not just percentage lift. Compare like country/device/source windows; flag seasonality and release effects. Success hypothesis: more search first-time downloads without reduced activation (first usable note, first successful Ask) or more refunds. No arbitrary statistically significant claim on a small sample. If impressions rise but conversion falls, refine proof/intent match; if impressions remain flat, keyword demand may be too small.
4. Rollback: retain baseline local metadata and ASC snapshots, publish the prior pack on the next editable version if needed. Do not alter the current review train without explicit go. No ads campaign is part of this request.

Known publishing path: central fastlane-configs app slug voice-notes. Direct asc_push.py is canonical where deliver silently drops metadata; it verifies the actual editable appInfo and version. Stage approved files into fastlane/apps/voice-notes/metadata/en-US only after approval, read ASC state, select the next legitimate editable release, upload using the existing pipeline, and read back all fields/screenshots. Do not create a version number or cancel review by guess. Current public version3.9.0, replacement3.10.0 waiting review.

Next decision for Shawn: approve this brain-dump/result-focused experiment, or retain broad AI-memory positioning. The draft is ready for review; live publication and new screenshot production are outstanding.
