# EEON ASO Research — 2026-09-10

Inputs: live fastlane metadata, `docs/superpowers/specs/2026-09-01-eeon-strategy-professional-ai.md`
(applecharts.com review-mining), `MEMORY.md` (competitive positioning + today's product pivot),
iTunes Search API (`itunes.apple.com/search`, real-time, US storefront) for head-term and long-tail
rankings, and iTunes Customer Reviews RSS for competitor review mining.

**Data-source caveat:** the iTunes Search API returns Apple's *search-relevance* ranking for a
term — a strong proxy for App Store search results, but not identical to the on-device ranking
algorithm (which also weighs a user's install history/location). Treat rank order as directional,
not exact. All counts below (`averageUserRating`, `userRatingCount`) are read live from the API
today, not estimated.

## 0. Positioning mismatch found before any keyword work (flag first)

**The live metadata still describes the AI-agent/personal-assistant product EEON pivoted away
from today.** Per `MEMORY.md`'s 2026-09-10 entries, EEON removed the AI Prompt recorder and
returned to "one record button, a note is a note" — and the brief explicitly says do not lean
on "AI prompts/agents." But the current App Store listing:
- Name: **"EEON: AI Personal Assistant"**
- Promotional text: *"...let authorized AI agents search your memory"*
- Description opens: *"Your personal AI assistant for iPhone... AI agents..."*
- Keywords include `personal assistant` and `MCP`

This isn't just an ASO opportunity, it's a product-truth drift (Rule #0 territory) — the store
listing overpromises "AI agent" behavior the app no longer has, and item 1 below shows
`ai personal assistant` is also the single most contested search term I found. All three
proposals below fix this.

## 1. Current live metadata (verbatim, from `~/projects/fastlane-configs/fastlane/apps/voice-notes/metadata/en-US/`)

| Field | Text | Chars | Cap |
|---|---|---|---|
| name.txt | `EEON: AI Personal Assistant` | 27 | 30 |
| subtitle.txt | `Personal AI assistant` | 21 | 30 |
| keywords.txt | `personal assistant,AI notes,voice notes,voice memo,transcribe,meeting notes,reminders,AI memory,MCP` | 99 | 100 |
| promotional_text.txt | `Use the phone in your pocket as your personal AI assistant. Ask EEON, track follow-ups, and let authorized AI agents search your memory.` | 136 | 170 |

Description opens: *"Your personal AI assistant for iPhone. Use the phone in your pocket as
private memory for ideas, decisions, meetings, reminders, project context, and AI agents..."*
(full file at `~/projects/fastlane-configs/fastlane/apps/voice-notes/metadata/en-US/description.txt`).

## 2. Head-term reality (iTunes Search API, US, `entity=software`, read live today)

| Term | Top 3–5 results (rating / rating count) | Verdict |
|---|---|---|
| `voice notes` | Apple **Voice Memos** (4.81 / 1,082,214), Voicenotes AI Notes & Meetings (4.77 / 6,845), Otter Transcribe (4.78 / 78,024), Voice Recorder & Audio Editor (4.72 / 452,297) | Unwinnable head-on — Apple's own system app owns #1 by two orders of magnitude. |
| `voice memos` | Apple **Voice Memos** (4.81 / 1,082,214) dominates; next is Voice Recorder & Audio Editor (4.72 / 452,297) | Unwinnable — literally competing with a pre-installed system app. |
| `ai notes` | Otter (78,024), Notability (455,628), Goodnotes (451,477), Minutes AI (14,008), Granola (4.96 / 12,892) | Saturated with 400k+ rated incumbents (note-taking giants, not voice-specific). |
| `voice to text` | Otter, Transcribe – Speech to Text (10,804), Speechify (522,838), Wispr Flow (15,339) | Saturated. |
| `ai meeting notes` | Otter, Granola (4.96 / 12,892), Minutes AI (14,008), Fireflies (4,990) | Saturated, and this is explicitly the positioning Shawn said NOT to claim (EEON doesn't join calls). |
| `transcription app` | Otter, Rev (4,271), Live Transcribe (7,697) | Saturated, generic utility term with weak tie to EEON's memory/RAG differentiator. |
| `ai personal assistant` | **Pocket** (4.90 / 5,308), Meta AI (243,306), Google Gemini (2,210,616), **ChatGPT (4.83 / 10,107,341)** | Most contested term found in this research. This is what the current name targets — confirms Shawn's "can't go head-to-head" read. |

Conclusion: every head term either has a system app, a 400k+-rated incumbent, or a
10-million-rated foundation-model app at #1. Matches the brief's premise exactly — the long-tail
list below is where the real opportunity is.

## 3. Long-tail target list (ranked by opportunity; all pulled live from iTunes Search API today)

| Term | Fit to EEON | Demand evidence | Contest level | Placement |
|---|---|---|---|---|
| **`ai memory`** | High — matches the locked positioning line "It's an AI memory" | Top results are almost all 0-rating apps: Lumo (0), Memora – AI Memory & Assistant (0), Mindverse (0), SecondBrain: AI Memory (5.0★/2), Memora: AI Memory (0), MyEcho (0). No established leader. | **Wide open** | Name + subtitle |
| **`second brain voice`** | High — "compounding memory" is EEON's durable differentiator per the strategy doc | All results 0-rated except SecondBrain: AI Memory (2 ratings). | **Wide open** | Keywords / subtitle |
| **`voice to reminders`** | High — real shipped feature (tasks → Apple Reminders) | AiRemindr (5.0★/1), AI Reminder: Voice To Do List (0) lead; no incumbent. | **Wide open** | Keywords |
| **`notes to reminders`** | High — same feature | Top result "Notes to Reminders" has 1 rating; rest of page is Apple Reminders/Todoist/Google Keep (adjacent, not direct competitors for this phrase). | **Very low** | Keywords / description |
| **`voice notes tasks`** | High — Reminders sync | NoteOS: Voice Notes & Tasks (27), In-Bot: Voice Notes to Tasks (5.0★/2), VoiceTask AI (0). | **Low** | Keywords |
| **`smart notes ai`** | Medium-high | Smart Notes: AI Note-Taker (0) leads; Smart Noter (2,313), CraftNote (4,583) mid-size. | **Low-medium** | Keywords |
| **`brain dump app`** | Medium — matches "quick thoughts while walking" use case | Brain Dump: AI Notes & Writing (63), Jot – Instant Brain Dump (41); skews ADHD-niche audience (Perch, Squirrel both 1 rating). | **Low** | Keywords |
| **`voice journal ai`** | Medium — matches "journal entries and personal reflection" use case | Untold – Voice Journal (2,193) is the only real incumbent; Day One (118,087) is adjacent but not "AI voice journal" specifically; Magic/Yuho both single-digit ratings. | **Low-medium** | Keywords |
| **`dictation notes ai`** | Medium | Mixed: Otter/Wispr Flow (established) alongside Owll (2,626), Unstuck AI Note Taker (2,685) — smaller players still visible. | **Medium** | Keywords |
| **`meeting notes reminders`** | Medium — validates the meeting-notes→reminders compound value prop | Agenda (3,676), SuperNote (4,473 / 8,396) are established; Apple Reminders itself shows up. Confirms demand for the *combination*, not a clean single-app win. | **Medium-high** | Description copy, not primary keyword |
| **`personal ai memory`** | Medium | Bee – Your Personal AI (2,598) leads; Limu AI – Memory Keeper (0), Orion Personal AI (0) trail. | **Low-medium** | Secondary keyword (overlaps `ai memory`) |
| `voice notes calendar` | Low-medium | Results are mostly generic planners (24me, Reminder apps) and Granola — weak direct match, treat as **estimate**, not confirmed demand. | Unclear — weak signal | Skip as primary; keep in description |
| `ask my notes` | Low | Results are generic notes apps (Standard Notes, Simplenote, SuperNote) — Apple's search isn't parsing this as a distinct query pattern. | Weak signal | Skip |
| `record thoughts` | Low | Results are noisy/off-topic (CBT/DBT apps, a vinyl-record scanner) — "record" is ambiguous to Apple's search. | Weak signal | Skip |
| `talk to text notes` | Low | Saturated: Goodnotes (451,477), Speechify (522,838), Otter, Voicenotes all outrank. | High contest | Skip as phrase |
| `mcp notes` | Very low | "MCP Notes" (0 ratings) is the only literal match; everything else is irrelevant. MCP is a developer/technical term with essentially no consumer search volume. | No real demand | **Drop from keywords** — currently spending budget on this |

## 4. Review phrases mined (competitor App Store reviews, iTunes Customer Reviews RSS, pulled live today)

Sources: Voicenotes AI Notes & Meetings (id 6483293628, Coping Hard Inc — the closest named
competitor per `MEMORY.md`), Letterly: AI Note Taker (id 6464049772), Audionotes (id 6736822144),
Otter Transcribe (id 1276437113). Most-recent reviews, mixed ratings.

**What people love (their own words):**
- "essential part of my life and my workflow... I couldn't do without it" — Voicenotes, 5★
- "Sometimes you just find software that works the way you think" — Letterly, 5★
- "I like to talk a problem out while walking and hiking and this app has been indispensable to
  my process" — Audionotes, 5★ (directly matches EEON's "quick thoughts while walking" use case)
- "someone who's always found it hard to take notes during discussions... lifesaver in recording
  and condensing information" — Audionotes, 5★
- "makes the recap from meetings very easy, and **things are not falling through the cracks**"
  — Otter, 5★ (strong phrase — ties directly to EEON's "the competitor is forgetting" positioning)
- "quick notes artist lyrics emails for business and a whole lot more" — Letterly, 4★ (breadth of
  use case)
- "the ability to add custom prompts" — Audionotes, 5★
- "Does not childishly censor your own words" — Otter, 5★ (trust/authenticity)

**What people complain about (validates Pillar 1 "trust is the moat" from the 09-01 strategy doc):**
- "Lost too many meeting notes... the app never captured a word" — Voicenotes, 1★
- "**trust, once lost, is hard to gain back**... In just two weeks... I've lost approximately three
  hours of very important recordings" — Voicenotes, 1★
- "Fundamental Reliability Problems" — Voicenotes, 1★
- "Daily usage limit not enough for what I need" — Voicenotes, 1★
- "Declined AutoRenew this Month; App Replaced: Replaced with [competitor]... which optionally
  sends voice & transcribed notes, plus generated action lists" — Voicenotes, 3★ (switching driver:
  action lists from voice notes)
- "Stole my money. I paid for lifetime access but they just took the money and won't respond to
  emails" — Letterly, 1★
- "Called my wife a HUSBAND instead of MY WIFE... This has gender all wrong" — Voicenotes, 2★
- "Make it free for premium features" — Otter, 4★
- "U HAVE TO PAY FOR EVERYTHING... pretty useless unless u wanna pay insane amounts of money"
  — Otter, 1★

These corroborate the 09-01 spec's applecharts findings (pricing pain #1, reliability #2 across
the category) and surface one new asset: **"falling through the cracks" is a ready-made subtitle/
description phrase that lines up with EEON's own "competitor is forgetting" line.**

## 5. Three metadata proposals

All verified programmatically against Apple's caps (name ≤30, subtitle ≤30, keywords ≤100) and
checked for keyword-field words that duplicate name/subtitle words (wasted character budget).

### Proposal A — Conservative
| Field | Value | Chars |
|---|---|---|
| Name | `EEON: AI Voice Memory` | 21/30 |
| Subtitle | `Notes, tasks & meeting recall` | 29/30 |
| Keywords | `journal,dictation,transcribe,reminders,second brain,calendar,decisions,commitments,brain dump` | 93/100 |

Rationale: smallest change from the live listing — keeps "voice" and "notes" (proven category
vocabulary) while dropping "personal assistant"/MCP for the wide-open `ai memory` term. Lowest
risk of confusing existing installed users mid-rename.

### Proposal B — Recommended
| Field | Value | Chars |
|---|---|---|
| Name | `EEON: AI Memory & Notes` | 23/30 |
| Subtitle | `Voice notes, tasks & recall` | 27/30 |
| Keywords | `second brain,journal,dictation,transcribe,meeting,reminders,decisions,commitments,brain dump,ask` | 96/100 |

Rationale: leads with `ai memory` (wide-open per §3) in the name itself — the highest-leverage
single word change available — while subtitle carries `voice notes` (proven vocabulary, still
needed for recall/discovery) and `tasks`/`recall` (validated white space, §3 rows 1–5). Keywords
add `second brain` (also wide open) plus category vocabulary without repeating name/subtitle words.

### Proposal C — Aggressive
| Field | Value | Chars |
|---|---|---|
| Name | `EEON: Your AI Second Brain` | 26/30 |
| Subtitle | `Voice notes, never forget` | 25/30 |
| Keywords | `journal,dictation,transcribe,meeting,reminders,decisions,commitments,calendar,recall,memory,ask` | 95/100 |

Rationale: bets fully on the two confirmed-wide-open terms (`second brain`, and `memory` via
keywords) plus the review-mined "falling through the cracks" insight, reworded as "never forget."
Highest upside if `second brain` searchers convert well, but it's a bigger identity change and
"second brain" carries a Notion/PKM-tool connotation EEON should make sure its screenshots and
first-run experience actually deliver on.

**My recommendation is B.** It captures the single biggest confirmed opportunity (`ai memory` in
the name) without over-rotating into "second brain" positioning that the rest of the app (a single
record button, not a PKM/wiki tool) doesn't visually back up.

## 6. Rewritten description — first 3 lines (shown before "more" truncation)

```
EEON is not a transcription app. It's your AI memory.
Press Record and talk — EEON turns rambling voice into clean notes, tasks synced to
Apple Reminders, and meeting context pulled from your calendar.
Ask EEON anything later: "What did I decide about pricing?" It remembers so you don't have to.
```

This replaces the current opening ("Your personal AI assistant for iPhone... AI agents...") with
the positioning line already locked in `MEMORY.md`, and states only shipped features (Record
button, Reminders sync, calendar context, Ask EEON/RAG) — no AI-agent or MCP framing up front.

## 7. What I could not verify

- **applecharts.com's live keyword-roadmap tool** (`/roadmap/[keyword]`) is a client-side app that
  takes ~20–30 seconds to compute results; `WebFetch` only captures the initial (unpopulated)
  page state on every attempt, including a retry aimed at the "cached" version. I did not loop
  further per the brief's instruction. I substituted the iTunes Search API (real Apple data, no
  rendering needed) for head-term and long-tail ranking evidence, and the iTunes Customer Reviews
  RSS feed for review mining — both are live, unmodeled data, just not applecharts' specific
  competition/winnability scores. The 09-01 spec's applecharts tables (pricing-pain #1,
  reliability #2 complaint counts) are the most recent successful applecharts pull and are cited,
  not repeated in full, above.
- **True on-device App Store search ranking** — the iTunes Search API is a strong proxy but Apple
  does not publish the live on-device algorithm, so exact rank positions (not just "who's present
  on page 1") are directional, not guaranteed.
- **Actual search volume** for any term — no tool available here returns raw monthly search volume
  (that data is proprietary to Apple/ASO platforms like Sensor Tower or AppTweak, which this
  environment has no access to). All "demand evidence" above is rank-presence and rating-count
  based, not volume-based, and is labeled as such throughout.
- **International markets** — everything above is US storefront only.
