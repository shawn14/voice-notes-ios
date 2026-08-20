# EEON Interface Redesign — Thesis

**Date:** 2026-08-20
**Evidence:** build 143 home screen, iPhone 16 Pro, dark mode
**Problem in one line:** the screen spends half its height organizing notes three
different ways before showing a single one.

---

## I. Three navigation systems are stacked, doing one job

### A. Category cards, week strip, and date headers all filter the same notes
Three controls, three visual languages, one function. The user must learn which
of three things to touch to answer "where is that note?" — and none of them is
obviously primary. A capture app should have **one spine**; everything else is
progressive disclosure.

### B. Half the viewport is chrome before the first note appears
Measured from the screenshot: greeting + date + "Tuned for you" pill + category
cards + section header + week strip + search ≈ **1000 of 2000 pixels**. The
first note title lands at the midpoint of the screen. On a capture-first app,
the content should start in the top third.

### C. Two of the three are actively misleading
The week strip shows **Aug 13–20**. The feed below it shows **May 29** and
**May 28**. Every day the strip offers leads to an empty result, while the notes
that exist are unreachable from it. A control that cannot reach the data it
appears to index is worse than no control.

---

## II. Nothing is sized to be read or reliably hit

### A. Text truncates and clips at three separate places
"Product De…" truncates inside a fixed 128pt card. The third category card is
sliced by the screen edge with no peek affordance or scroll hint. The leftmost
day chip is cut in half. Every one of these is the app deciding the user
doesn't need to finish reading.

### B. The type scale has no hierarchy below the title
Note title, timestamp row, and preview line use three sizes that are too close
together, and the preview is set in a grey close to the metadata grey. The eye
gets no help deciding what to read first, so it reads everything or nothing.

### C. Touch targets and controls are mutually inconsistent
A 40×52 day chip, a 128pt-wide card, a bare text "Clear", a thin checklist
glyph, and a filled avatar circle all coexist in one header. Apple's minimum is
44×44; several targets are under it, and no two controls share a shape language.

---

## III. The information architecture doesn't match the data

### A. The most prominent card is the absence of organization
"Unfiled — 15" is the first and largest category, which means the loudest thing
on screen advertises that most notes aren't categorized. Categories derived from
an AI's first topic guess ("Ai", "Product De…") aren't stable enough to lead the
screen.

### B. Section labels don't label their sections
"Your notes" sits below the category cards, above the week strip, above search,
above the feed — so it labels none of them unambiguously. "Clear" appears next
to it, applying to filters that live in two different rows.

### C. Layout truth is scattered across three eras of the app
Some of home comes from the persona-layout system, some from the simplification
passes, some from the Pocket clone work. There is no single description of what
home *is*, so each change has been additive.

---

## Conclusion

The redesign is not a restyle — it is a **reduction to one spine plus one
control**. Time is the spine: notes are a reverse-chronological stream with day
headers, because that is how capture actually happens and it is the only
organization that is always correct. Everything else — category, date jump,
search — collapses into a **single filter affordance** that is invisible until
invoked.

Three rules govern every pixel after that:

1. **Nothing truncates.** If a label doesn't fit, the container grows or the
   label wraps — never an ellipsis on a one-word-too-long category.
2. **One type scale, one target size.** A defined ramp for title / meta /
   preview with real contrast between steps, and a 44pt minimum on everything
   tappable.
3. **Content starts above the fold.** Chrome earns its height or it goes; the
   first note title should be visible without scrolling.

The measure of success is simple: open the app, and the first thing you see is
what you said — not the machinery for finding it.

---

## Open questions for the research loops

1. **Platform truth:** exact HIG minimums for targets, Dynamic Type behavior,
   and dark-mode contrast ratios this design must satisfy — and whether the
   codebase currently supports Dynamic Type at all (fonts appear hardcoded).
2. **Prior art:** how the best note/capture apps resolve date-plus-category
   without stacking navigations, and what they put above the fold.
3. **Consistency audit:** every screen and settings surface inventoried for
   type sizes, spacing, and control shapes, so the redesign can enforce a
   single system rather than fixing home alone.
