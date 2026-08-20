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

## Open questions for research loops

1. **Mode pill + Auto-Pilot / Reasoning templates** — what does "Normal Mode" switch, and are Auto-Pilot/Reasoning processing modes rather than formats?
2. **Task system mechanics** — are tasks two-way synced with external apps, do they have reminders/notifications, how do they attach back to source notes?
3. **Packaging** — what exactly is free vs Pro (retention limits, Ask caps), and how does the 14→30-day trial ladder actually convert?
