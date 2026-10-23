---
name: typography
description: >
  Lambda's type system — the two families, the measured size ladder, weights,
  tracking, line height and the minimum size every surface allows. Use when
  choosing a size, weight or family for any text, when a label reads too
  small, or when reviewing a screen for type consistency, so type stays one
  ladder instead of drifting per screen.
---

# Lambda Typography

The ladder below is the **only** copy of the sizes. `AppTextStyles`
(`lib/core/styles/app_text_styles.dart`) is the code spelling of it; a skill
or doc that lists a different ladder is stale — fix it rather than following
it. Contrast and touch targets are the **accessibility** skill's; this skill
is size, weight, family and rhythm of the letters themselves.

## 1. Two families, one split

| Family | Token | What it draws |
|---|---|---|
| UI | `AppFonts.ui` | everything human-readable: titles, prose, notes, buttons, questions |
| Mono | `AppFonts.mono` | numbers, weights, reps, dates, IDs, and **uppercase micro-labels** (column heads, section labels, eyebrow strings) |

- On iOS `ui` resolves to `.SF Pro` (the system face, so stock chrome — date
  pickers, dialogs — matches); every other platform falls back to bundled
  Manrope. Mono is JetBrains Mono everywhere. Never name a family directly;
  always `AppFonts.ui(...)` / `AppFonts.mono(...)`.
- Both helpers pass size explicitly. There is **no implied default**: a call
  without `fontSize` inherits whatever body style the ancestor set, which is
  how 10px text appears where 14 was intended. Every call site states its size.

## 2. The ladder — the only copy

`AppTextStyles` exposes these names; use the name, never the number.

| Token | px | Role |
|---|---|---|
| `xs` | 12 | **the label floor** — mono micro-labels, badges, dates, eyebrow strings, counters, gaps ("34 days prior") |
| `caption` | 13 | a quiet caption that still carries information: a sheet's eyebrow, an all-time count |
| `sm` | 14 | buttons, PR lines, dense row text, empty states |
| `body` | 15 | **the workhorse** — lesson bodies, prose, the lead line of an entry |
| `md` | 16 | input text, list rows, modal body |
| `lg` | 18 | titles inside a sheet or card, page titles |
| `xl` | 22 | display headings (sparingly) |
| `xxl` | 30 | display headings (sparingly) — a statistic's number |

A size that is not on the ladder is a bug in the call site, not a new rung: if
a surface genuinely needs one, it is added to `AppTextStyles` first (name, not
number), and to this table in the same change.

## 3. Floors and minimums

- **12 is the floor for any text the user reads.** A capsule badge is still
  text — the variation badge in the PR sheet was drawn at 11 and moved to 12
  for exactly this reason (2026-10-21).
- The 10–11px labels older production screens carried were cleared in the
  2026-10-22 app-wide rollout. No production or shared screen draws below 12
  now, and `test/typography_guard_test.dart` fails the build if one appears
  (`lib/features/dev/` demos are the only exemption).
- Icons inline with text are ≥ 14 (`Icons.*` at 14–20); an icon-only control's
  glyph is 18–20 (see **frontend-design** §5).
- Prose is never mono. Mono is for data and labels; a sentence in mono reads as
  code.

## 4. Weights

| Weight | Role |
|---|---|
| w400 | prose, body text |
| w500 | secondary ink — dates, captions, quiet values that must still be read |
| w600 | labels, buttons, section heads (the app's default emphasis) |
| w700 | data emphasis — the lead value of an entry, a PR line, an uppercase badge |
| w800 | titles and headers |

Weight carries hierarchy **after** size; on the same size, one step of weight
(w500 → w600) is the cleanest separation there is.

## 5. Tracking

- Uppercase mono only: `letterSpacing: 0.6–0.8`, and 0.8 is the ceiling —
  `test/typography_guard_test.dart` rejects anything beyond it outside the dev
  demos. That is the signal that says "this string is a label, not a
  sentence".
- Never track `ui` prose. Never track a mixed-case mono value (a weight, a
  reps count, a date).
- Tracking is not a substitute for size: a tracked 10px label is still a 10px
  label.

## 6. Line height

- Multi-line prose sets `height: 1.3–1.4` — lesson bodies, notes, descriptions.
  The reference is the lab Lessons sheet: `AppTextStyles.body`, `height: 1.35`.
- Single-line labels, values, dates and badges set **no** height — the default
  is correct and a height on a one-line row only distorts its box.
- A wrapped `Text` inside a shared `Row` needs a bound (`Expanded` /
  `Flexible`); without one it overflows instead of wrapping.

## 7. Order of decisions

When styling a piece of text, decide in this order and stop at the first that
answers:

1. **Size** — what role is this on the ladder? (Never "what fits".)
2. **Weight** — how much does it matter relative to its neighbours?
3. **Ink** — `primary` for content, `inkSecondary` for secondary text that
   must be read, never `muted` for text (**accessibility** §3). The widget
   guard is `expectReadableText` from `test/support/readable_text.dart`.

Colour is the last lever, never the first: reaching for a dimmer ink to quiet
something that is actually too large is the drift this skill exists to stop.

## 8. Checklist

- [ ] Size is an `AppTextStyles` token, not a literal.
- [ ] Family follows the split: data/labels mono, everything else ui.
- [ ] Nothing informational is below 12; badges included.
- [ ] Weight is one of w400/w500/w600/w700/w800 and matches the role.
- [ ] Tracking is on uppercase mono only.
- [ ] Multi-line prose has `height: 1.3–1.4`; single-line text has none.
- [ ] Ink comes from **accessibility**'s role table — not `muted` for text.
- [ ] The surface runs `expectReadableText` (`test/support/readable_text.dart`)
      and `test/typography_guard_test.dart` still passes.
