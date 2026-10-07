# Voice-note app benchmark and the four gaps closed (2026-10-06)

Goal from Shawn: look at the top voice-note apps (Pocket first), list the four
most important features EEON lacks, and close them.

Read on 2026-10-06 from first-party sites, docs and App Store listings: Pocket,
Plaud, Granola, Voicenotes, Otter, Letterly, AudioPen, Wispr Flow, Superwhisper.
Reddit and web.archive.org were unreachable, so user voice comes from Trustpilot,
Product Hunt and App Store reviews. Pocket publishes no dated changelog (every
App Store note says "Bug fixes"), so "new since August" could not be dated.

## What the category leads with

1. Ask across the whole archive (Plaud, Granola, Voicenotes, Otter, Pocket).
2. Capture that does not lose things. The loudest complaints are lost or
   unsynced recordings ("your notes are now GONE", Voicenotes review; Pocket
   device resets and sync failures on Trustpilot).
3. Capture from anywhere without friction: Apple Watch (Granola shipped it
   2026-07-28; Voicenotes, Letterly, AudioPen have it), Lock Screen, Action
   Button, widgets.
4. Speaker labels that are right, and a way to check them against the audio.
   Otter leads with tap-a-word playback; a Pocket reviewer names its absence.
5. Templates and rewrite styles, including translation (Letterly "convert voice
   notes to any language", AudioPen, Superwhisper).
6. MCP and workflow integrations (now in Granola, Voicenotes, Otter, Letterly,
   AudioPen, Pocket).
7. A system-wide dictation keyboard (Letterly, Voicenotes, AudioPen converging
   on Wispr and Superwhisper).
8. A Mac or web companion (every app).

## Checked against EEON's source

Already in EEON: Ask with scopes and follow-ups, speaker identification, mind
map, templates and Adjust, tasks with Reminders sync, calendar context, MCP
agent access, Live Activity, Control Center control, App Shortcuts, widgets,
transcription language choice, custom vocabulary, audio/PDF/image/URL import.

Missing, and closed in this pass:

| Gap | Who ships it | What EEON had |
|---|---|---|
| Apple Watch capture | Granola, Voicenotes, Letterly, AudioPen | No watch target |
| Recently Deleted (30 days) | Pocket ("kept in the Recycle Bin for 30 days") | Delete destroyed the note and audio at once, from three screens |
| Tap a sentence to hear it | Otter; Pocket lacks it | Whisper's segment times were fetched then discarded |
| Translate a note | Letterly, AudioPen, Superwhisper, Otter (reported) | Nothing reachable |

Missing, and deliberately left:

- **Mac/web app.** A separate product. The agent connector covers reading notes
  on a computer today. Revisit as its own decision.
- **Dictation keyboard.** Also a separate product; Shawn uses Wispr for it.
- **Combine recordings into one summary** (Pocket, AudioPen), **emailed
  summaries** (Pocket Pro), **cross-recording voice print** (Pocket),
  **mark a moment while recording** (Plaud only), **ask about one note**
  (reported for Otter and Granola). Smaller; next candidates.
- **Third-party task and CRM integrations.** Declined 2026-09-25 (Apple-only
  task sync).

## Pricing seen (for reference)

Pocket Pro $19.99/mo or $239.88/yr plus a $99 device; free tier keeps summaries
30 days. Plaud Pro $99.99/yr, Unlimited $239.99/yr. Granola Business $14/user/mo.
Voicenotes $14.99/mo or $89.99 to $99.99/yr in the App Store. Otter Pro $16.99/mo.
Letterly $19.99/mo, lifetime $199.99+. EEON is $9.99/mo or $79.99/yr.
