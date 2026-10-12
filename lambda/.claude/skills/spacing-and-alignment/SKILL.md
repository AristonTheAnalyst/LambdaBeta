---
name: spacing-and-alignment
description: >
  Rules for positioning controls in Lambda's chrome: insets are measured
  from a control's BOX (padding + border), not its text; box-edge parity
  versus glyph ink; centered content centers on the SCREEN, never on the
  leftover gap between controls. Use when placing or moving anything in a
  header, row, or bar; when a chip replaces an icon in a slot; or when
  something looks misaligned against a screen edge or its neighbour.
---

# Spacing & alignment — position the BOX, centre on the SCREEN

`frontend-design` §4 owns the spacing *rhythm* (which token goes between
what). This skill owns *positioning*: where a control's edge lands, and
what "centred" means. Get this wrong and the layout is still valid Flutter —
just visibly off, which no analyzer and no text-asserting test will catch.

## 1. A control's spacing is its BOX, not its text

Every boxed control (chip, pill, `GlassButton`, bordered `Container`) adds
its own space — padding, border, radius. `Container(padding: 8)` around one
word is ~16 px wider than the word. The offset you pass (`right: 16`, a
`Positioned`, a Row gap) lands on its **border**, and the border is the edge
the eye measures against the screen corner.

A bare `Icon` in the same slot behaves oppositely: the glyph carries a side
bearing inside the icon box (the 18 px back chevron at `left: 16` shows ink
from ~22). So an icon at 16 and a chip at 16 do **not** read equal — and
that is accepted: the app aligns **boxes**, not ink (`PageHeader` holds
`left`/`right` at 16 whatever they contain).

**The corollary that bites: swapping a bare icon for a boxed chip in a slot
means re-deriving the offset.** A `right: 6` tuned for the 20 px trash glyph
(ink starts ~5 in) leaves a chip's border jammed ~10 px off the corner. The
chip takes the header's own 16. (2026-10-07: the review header's Note chip
replaced the trash and inherited its inset.)

## 2. Centred content centres on the SCREEN

The title band is symmetric — `left: 88, right: 88` — in `PageHeader` and in
the planner's `_editableHeader`. That is what "centred" means here: the text
sits on the screen's centre line, **not** in the gap left over between the
controls. Do not narrow one side to dodge a wider control; the centre moves
with it (the review's Note chip arrived and the workout name slid 22 px
left, 2026-10-07). Give the controls their room instead: the band's right
edge (314 on a 402-wide screen) stays clear of a chip at `right: 16`
(starts ~334), so even a long name cannot run under it.

## 3. The concrete numbers

- Header controls: `left: 16` / `right: 16`; title band `88 / 88`
  (`PageHeader`, `_editableHeader`). An icon-only slot sitting closer (the
  planner's trash at `right: 6`) is the exception, and only for a bare
  glyph whose ink supplies the rest of the gap.
- Chips within a row: `AppSpacing.sm` (8) between chips; 10 between a chip
  and a bare icon.
- A control inside a card is inset against the **card's** padding, not the
  page's — decide which box it actually sits in before choosing a number.

## 4. How to check

- Scale a simulator screenshot to logical size (`sips -z 874 402 …` on the
  iPhone 17) and compare the two gaps by eye — a few px is visible at a
  header corner.
- Or pin the geometry in a widget test: the chip's global `dx`/`right` edge
  against the screen width, and a centred title's centre `dx` against
  `physicalSize.width / (2 * devicePixelRatio)`.
