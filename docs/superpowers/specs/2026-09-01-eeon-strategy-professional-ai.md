# EEON Strategy — The Trustworthy Memory for AI-Using Professionals

**Date:** 2026-09-01
**Inputs:** Pocket teardown (`docs/pocket-teardown-thesis.md`), Circleback product read,
EEON current state (this session), and live App Store review mining via
applecharts.com for `ai meeting notes` and `voice notes`.

---

## 1. What the market actually complains about (review evidence)

applecharts.com review roadmaps, newest reviews, two adjacent keywords:

| Signal | ai meeting notes | voice notes |
|---|---|---|
| Pricing / subscription pain | **127** complaints (#1) | **93** complaints (#1) |
| Reliability / bugs / save fails | 41 (#2) | 38 (#2) |
| Support / customer service | 32 (#3) | 26 (#3) |
| Login / account / cancellation | 32 (#4) | 11 |
| Performance / battery | 19 | 10 |
| Apple Watch (requested AND buggy: corrupted files) | 3 req / 8 bugs | 2 req / 7 bugs |
| Loved + rising | Apple Watch, transcription quality | **Videos/coaching +83%**, simplicity |

Gaps no top app fills: reliable support, performance, simplicity/fewer taps,
Apple Watch done right, coaching/onboarding.

**The category's problem is not features — it is trust.** The top four
complaints in both niches are bait pricing, things that break, no one to help,
and being unable to cancel. Feature requests barely register by comparison.

## 2. Where EEON stands

- **Ahead of Pocket** on the personal-memory axis: no puck, background capture on
  a stock iPhone, and intelligence that *compounds across notes* vs Pocket's
  per-conversation reset. Same four surfaces, a third of the price, no hardware.
- **Deliberately behind Circleback** on live meetings: no meeting bot auto-join,
  no cloud automations/CRM write-back, no team workspace. These conflict with the
  locked privacy-first, personal, Apple-native direction and should stay out.
- **Own weak spots (this session):** Whisper hallucinates stock phrases on silent
  audio; the MCP "your AI can read your memory" bridge failed silently on an
  expired token; capture is manual in a calendar-driven life; no auto-diarization.

The uncomfortable overlap: EEON's own weak spots ARE the category's #2 complaint
(reliability) and undercut its #1 differentiator (the AI bridge).

## 3. Strategy — three pillars

### Pillar 1 — Trust is the moat (win where the whole category loses)
The category fails at pricing honesty, reliability, support, and cancellation.
EEON wins by making those a feature, not an afterthought.
- Transcription that never fabricates. A memory tool that invents content is dead.
- Nothing fails silently: save confirmations, MCP connection health, visible sync.
- Honest monetization: no surprise limits mid-use, one-tap visible cancel, a clear
  free/paid line. Not cheaper for its own sake — transparent. (Locked: free
  download + IAP, $9.99/$79.99.)
- A real in-app help/support surface (no top app has one).

### Pillar 2 — Effortless professional capture (beat Pocket's friction, close
Circleback's manual gap within the privacy line)
- Calendar-triggered auto-record: offer to start when a scheduled meeting begins.
- Apple Watch capture done RIGHT — requested across the category and buggy
  (corrupted files) in every app that ships it. Open lane if we nail reliability.
- Keep the stock-iPhone edge: Action Button / Siri / Control Center / lock screen.

### Pillar 3 — Compounding, AI-native memory (the durable differentiator)
- The extraction + compiled-knowledge pipeline that compounds over time.
- MCP interop as a first-class, monitored feature: "your Claude / ChatGPT / Cursor
  reads your memory," with connection status and re-auth.
- Automatic speaker diarization so multi-person meeting notes say who said what.

## 4. Feature roadmap (ranked by evidence x fit)

**Now — trust repair (blocks credibility):**
1. Fix Whisper silence-hallucination (verbose_json + no_speech_prob + min-duration
   gate). Reliability is complaint #2; this is our own bug. 
2. MCP connection health + re-auth prompt. The AI bridge is the #1 differentiator
   and it failed silently this session.
3. Monetization honesty pass: audit for surprise limits, make cancel obvious,
   clarify free vs Pro. Pricing is complaint #1 category-wide.

**Next — effortless capture + meeting credibility:**
4. Calendar-triggered auto-record (Circleback gap, fits our calendar context).
5. Apple Watch capture, reliability-first (open lane; everyone else corrupts files).
6. Automatic diarization (biggest honest feature gap vs both competitors).

**Later — category-gap polish:**
7. In-app help/support surface (no top app promises support).
8. Coaching onboarding that ends in the rambling-note -> clean-decisions transform
   ("videos/coaching" is loved and rising +83%).
9. Continue the fewer-taps simplicity pass (swipe actions, compact settings — done).

## 5. What NOT to build
Meeting bots, cloud automations/CRM write-back, follow-up email sending, hosted
API write-back, team workspaces, dark theme (light-only is locked). Chasing
Circleback's integration surface would trade away the privacy-first wedge that is
itself the selling point to security-conscious professionals.
