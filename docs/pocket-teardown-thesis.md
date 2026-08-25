# Pocket Teardown → EEON Clone Thesis

**Date:** 2026-08-20
**Source:** 24 in-app screenshots (onboarding, paywall, App Store previews) + heypocket.com
**Purpose:** Establish what Pocket actually is, where it is weak, and what EEON builds.

---

## I. Pocket is an onboarding funnel wrapped around a recorder

### A. The funnel is device-first and permission-heavy
- Order: sign-in (Apple / Google / Email) → permissions gate → device pairing → paywall.
- Permissions screen demands Bluetooth\*, Location\* (required for BT/WiFi), Notifications; **Continue stays disabled until toggled on** — a hard gate before the user has seen any value.
- Pairing requires the physical puck: hold the side button 5 seconds, keep it close, Bluetooth on, "Looking for Pocket" spinner. **No device, no app.** The sign-in screen even links "Don't have a device? Get one now."

### B. Monetization is aggressive and front-loaded
- In-app price is **$239.99/year** — $40 above the $199 advertised on their site.
- Trial ladder: 14 days by default, then a modal "upgrades" you to **30 days free** if you hesitate — a classic exit-intent downsell before you've recorded anything.
- The paywall shows a dated trial timeline (unlock today → 14 days free → reminder at day 12 → charged at day 14) and a five-card carousel: unlimited saved summaries, speaker names, unlimited Ask, app connections.

### C. The implication for EEON
- Every step of that funnel is friction EEON does not have: no puck, no pairing, no Bluetooth/Location gate, no shipping.
- EEON's onboarding can be **sign in → pick what you do → record**, and the first recording can happen before any paywall.
- At $79.99/year EEON is **a third of Pocket's in-app price** with no $99–$199 hardware purchase in front of it.

---

## II. The app's real product is the note pipeline, not the hardware

### A. Home is a dated capture stream
- Search with a filter affordance, a **mode pill** ("Normal Mode"), a Sync control, and an overflow menu.
- Entries group under date headers (TODAY, AUG 5 / YESTERDAY, AUG 4) with **time · duration · tag** metadata per row.
- A single dark **Record** pill floats bottom-right. Desktop mirrors this with a sidebar: Home / Ask Pocket / Meetings.

### B. The note detail is a template-switchable document
- Title, then `date · tag`, then a **"Summary ⌄" dropdown** — the summary *format is a runtime choice on the note*, not a fixed render.
- Body renders as headed sections (Overview / Proposals / Customization Options…), not a wall of prose.
- Sibling surfaces: real-time transcript with timestamps and speaker avatars, and a mind-map node graph.

### C. Three satellite surfaces carry the rest
- **Tasks**: their own screen, checkboxes grouped by date, due dates and tags per task, "+ Add Task" — tasks are first-class objects, not chips inside a note.
- **Ask**: a chat over your history that suggests the *next* question ("what do I need to do next before I forget something important?").
- **Templates**: a long catalog — Auto Detect, Auto-Pilot, Reasoning, Meeting Note, Call Summary, Speech Outline, Interview Summary, Dictation, Main Points, Strategy Session, Persuasive — plus "Create New Template".

---

## III. EEON already owns the hard half and can beat the soft half

### A. What EEON has that is equal or better
- **Capture**: Action Button / Control Center / Siri, locked-phone background recording, Live Activity, unlimited length, call auto-resume, crash recovery. Pocket needs a $99 puck to match what a stock iPhone now does in EEON.
- **Intelligence**: extraction of decisions / actions / commitments / people / tone, key-takeaways-first structured enhancement written in the user's own voice, RAG Ask, compiled knowledge that *compounds across notes* — Pocket's AI is per-conversation only.
- **Integrations**: Reminders (→ iCloud/Google/Outlook) and markdown folder export (→ Drive/OneDrive/Obsidian) both shipped without a single OAuth screen; Pocket demands Google contacts + calendar scopes up front.

### B. What EEON must build to reach parity
- Home: date-grouped stream showing **duration and category** per row, with the record control as the one floating action.
- Note detail: **format switcher on the note** + sectioned body + transcript view.
- Tasks: a real screen — checkboxes, due dates, grouping by day.
- Template catalog: broad, nameable, user-extendable (EEON has the engine; it needs the catalog and the picker).
- Mind map: the one genuine feature gap.

### C. Where EEON should deliberately beat them
- **No hardware, no pairing, no Bluetooth/Location gate** — value inside 30 seconds of install.
- **Profession presets** (Student / Lawyer / Doctor / Sales / Founder / Therapist) beat a flat template list: the persona picks the default format *and* shapes extraction *and* names the notebooks, from one tap.
- **Honest pricing**: $79.99/yr vs $239.99/yr in-app, no exit-intent trial games.
- **Compounding memory**: notes that build a knowledge base across time, versus Pocket's island-per-conversation model.
- **Privacy posture**: on-device + iCloud with no third-party account scopes required.

---

## Conclusion

Pocket's moat is not its software — it is a contact microphone and a shipping box. Strip the puck away and what remains is a dated capture stream, a template-switchable note, a task list, and a chat over history: all of which EEON either already has or can build in days on top of a capture stack that is *better* than Pocket's, because it needs no hardware at all.

The clone target is therefore not "copy Pocket's app" but **"ship Pocket's app minus its friction and plus EEON's memory"**: same four surfaces (stream, note, tasks, ask), same runtime format switching, none of the pairing, at a third of the price, with intelligence that compounds instead of resetting at every recording.

---

## Research findings (loop 3 — packaging, 2026-08-20)

**The headline: Pocket's app does not work without the puck.** Their own "5 steps"
page makes pairing step 1 and states the app cannot function without a paired
device; the docs, and third-party reviews, agree. The *device* is the recording
engine (64GB onboard, records away from the phone); the app is a companion.
There is no phone-mic-only mode. The one partial exception is a desktop beta
that captures Zoom/Teams/Meet audio.

**What this changes:** Pocket is not a software competitor at all for the ~100%
of people who don't own the hardware. EEON's competitor set is Otter, Letterly,
Voicenotes, Audionotes — and against *Pocket specifically*, EEON's pitch is not
"cheaper Pocket," it's **"Pocket's app, no puck required."** Every Pocket
review complaining about shipping delays is a person EEON could have served
that day.

**Pricing, corrected:** public sources uniformly list **$199/year and
$19.99/month**; the in-app sheet in Shawn's own screenshot showed **$239.99/year**
with a 2-week trial (unconfirmed publicly — possibly a price change, an A/B
test, or an annualized monthly SKU). Either way EEON at $79.99/yr undercuts by
2.5–3×, with no hardware purchase in front of it.

**Free vs Pro (confirmed):** Free = standard-accuracy transcription, **2 Ask
messages/day**, **summaries deleted after 1 month**, mind maps, plain-text
export. Pro = permanent summaries, highest-accuracy transcription, speaker-name
detection, unlimited Ask, advanced models, daily highlights, custom templates,
attachments, audio + full-format export, priority processing, and **recordings
up to 4 hours**.

**Two competitive gifts in that list:**
1. **They cap recordings at 4 hours, and only on Pro.** EEON has no cap at all,
   for anyone — that's now a headline feature, not an implementation detail.
2. **They delete free users' summaries after 30 days.** EEON keeps everything
   forever, locally and in the user's own iCloud.

**Their top complaints → our design targets:** shipping delays and slow support
(structurally impossible for us — no hardware); **billing/entitlement bugs where
Sign in with Apple's private-relay email breaks purchase-to-account matching**
(EEON gates `isPro` on subscription AND `AuthService.isSignedIn` — audit this
exact failure mode before launch); transcription degrading with cross-talk and
noise; Bluetooth reconnection failures (N/A for us).

## Research findings (loop 1 — modes & templates)

- **"Normal Mode" is device state, not an AI mode.** The pill reflects the puck's
  physical slider: *Normal* (two studio mics, room conversations) vs *Call* (contact
  mic against the phone's earpiece). **EEON should not build this** — it's hardware
  plumbing we don't have and don't need.
- **"Auto Detect"** is a summary theme that picks the format from content
  automatically. Cheap for EEON: the extraction pass already classifies intent.
- **Custom templates are structured, not free-prompt** — Name + global instructions
  (tone/style) + reorderable **Sections**, each with a title and its own extraction
  instructions; docs recommend 3–6 focused sections. Pro-gated. This is a better
  design than a raw prompt box and is worth cloning outright.
- **Ask has a model picker**: everyone defaults to a "Thinking" model, Pro can
  escalate to a stronger one for hard questions.
- **Unconfirmed:** "Auto-Pilot Mode" and "Reasoning Mode" appear in the in-app
  theme list but in no public doc, forum, or changelog. Treat any explanation as
  speculation; check the live app before cloning them.

## Research findings (loop 2 — tasks)

- **Sync appears one-way (Pocket → external app)**, never officially stated. Their
  own webhook API is outbound-only (`action_items.updated`), community guidance
  says "export," and a user asking for Reminders→Pocket sync got partial results.
  EEON's Reminders push is therefore already at parity; **two-way completion sync
  would beat them**, and it's easy on EventKit.
- **Every task references its source recording** ("never lose the *why* behind the
  *what*"). EEON already stores `sourceNoteId` on every `ExtractedAction` — the
  data is there, the screen isn't.
- **Tasks drive notifications and a home-screen widget**, plus a morning summary of
  pending items.
- **Due dates start from speech** ("...by Friday 5pm" is auto-detected) and are
  confirmed with a tap-to-schedule step. EEON already parses spoken deadlines into
  Reminders due dates.
- **Two tag systems**: conversation tags (user-created *and* AI-suggested) and
  separate color-coded **task labels** managed in the checklist.

## Open questions for research loops

1. **Mode pill + Auto-Pilot / Reasoning templates** — what does "Normal Mode" switch, and are Auto-Pilot/Reasoning processing modes rather than formats?
2. **Task system mechanics** — are tasks two-way synced with external apps, do they have reminders/notifications, how do they attach back to source notes?
3. **Packaging** — what exactly is free vs Pro (retention limits, Ask caps), and how does the 14→30-day trial ladder actually convert?

## Gap status (2026-08-25)

Sources: heypocket.com, their announcements feed (Nov 2025 → May 2026), and
the code. Graded feature by feature.

**Parity or better (closed 08-19 → 08-21):** background capture without the
puck · 120+ languages · auto-summaries + Pro auto-format · action items +
Tasks screen · Reminders sync · Drive/OneDrive/Obsidian export · Ask with
suggested follow-ups · structured custom templates + favorites · format
switcher / regeneration · widgets (home, lock, Control Center) · share link
with rich preview · audio/PDF/image/URL import · offline pending-retry ·
bulk export · folders (Notebooks) · flashcards (Pocket has none).

**Closed today (three loops):**

| Pocket | Shipped | EEON |
|---|---|---|
| Custom vocabulary dictionary | Dec 2025 | `TranscriptionVocabulary` → Whisper `prompt`; user terms + names EEON already extracted. Pocket makes you type the list; EEON fills most of it in. |
| Daily highlights (Pro) | Nov 2025 | `TodayHighlightsView` — the Tier-3 `DailyBrief` was generated daily and shown nowhere. Zero extra API calls. Not Pro-gated (Shawn's call). |
| Calendar integration (Apple / Google / Outlook) | Nov 2025 | `CalendarContextService` — one EventKit read covers all three; note gets the meeting title + attendees, AI title and extraction get them as context. |

**Open, deliberately:** mind map / visual summaries (TODO #7, presentation
only) · MCP / ChatGPT / Claude (TODO #4, needs a server) · Todoist / Linear /
Asana / ClickUp / TickTick (TODO #6, OAuth per app) · speaker names (Whisper
can't diarize) · dark theme (light-only, 08-20) · Ask model picker · Ask
attachments · memory import from ChatGPT · "Pocket Wrapped" · desktop/web.

