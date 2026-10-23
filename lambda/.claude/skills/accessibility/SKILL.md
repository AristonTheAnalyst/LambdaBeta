---
name: accessibility
description: >
  Lambda's WCAG floor — the measured contrast pairs per ground, the ink roles
  that pass, touch-target minimums, semantics labels, disabled states and text
  scaling. Use when picking a text colour, drawing an icon-only control, or
  checking that a sheet reads for low-vision users. Every ratio here is
  measured against the actual composite ground, not assumed from the token.
---

# Lambda Accessibility

The dark theme is the default, and it is the one that fails: `muted` sits
below WCAG AA for text, which is why — since the 2026-10-22 app-wide rollout —
it carries only decoration and disabled chrome and **never an informational
string**. This skill owns the ink roles and the numbers behind them. Type
sizes are **typography**'s; recipes and tokens are **frontend-design**'s.

## 1. The floor

| What | Minimum | Notes |
|---|---|---|
| Normal text | **4.5:1** | every string in the app — the 3:1 large-text allowance starts at 24px (18pt) regular / 18.7px bold, which these sheets do not reach |
| Large text | 3:1 | ≥ 24px regular or ≥ 18.7px bold; rare here — do not lean on it |
| UI boundaries, icons, focus rings | 3:1 | borders, chevrons, the pin glyph, toggle outlines |

Ratios are computed with the WCAG relative-luminance formula:
`(L1 + 0.05) / (L2 + 0.05)`, lighter over darker. Measure against the colour
that is **actually painted behind the text** (see §4), not the token you think
is under it.

## 2. The measured table — dark theme (the default)

Grounds: `surface` `#2E2E2E` · `surfaceHigh` `#363636` · primary glass
`#403E3C` · accent glass `#41382E` (glass = `withAlpha(26)` over `surface`).

| Ink | on `surface` | on `surfaceHigh` | on primary glass | on accent glass | Verdict |
|---|---|---|---|---|---|
| `primary` `#DDCAB7` | 8.54 | 7.60 | 6.70 | 7.22 | safe anywhere |
| `inkSecondary` `#C0A992` | **6.03** | **5.37** | **4.73** | **5.10** | safe anywhere |
| `accent` `#EB912B` | 5.57 | 4.96 | **4.37** | 4.71 | safe except **on a primary glass** — never draw accent text there |
| `muted` `#9E8470` | **3.87** | **3.45** | **3.04** | **3.27** | **never text** |

- `accent` on `accentBg` (`#3A2810`, the solid accent chip) is 5.78 — fine.
  Solid `GlassButton`s ink with `AppColors.bg`: 9.52 on a primary fill, 8.68
  on success, 6.21 on accent; the danger solid uses `dangerText` (white),
  5.44 on `danger`. The gap above is the primary glass specifically.
- The page ground `bg` `#262626` changes the numbers again: `muted` 4.32
  (still failing), `accent` 6.21, `inkSecondary` 6.72.
- The light theme (`monoLight`) is comfortable: `inkSecondary` 6.27 / 5.79 /
  5.32 on `surface` / `surfaceHigh` / `surfaceLow`, `primary` 15.82. Its
  `muted` `#6B6B6B` passes on the white page (5.33) and on `surface` (4.85)
  but fails on `surfaceHigh` (4.47) and `surfaceLow` (4.11) — the same rule
  applies, just less loudly.
- Re-measure if a token value changes: the numbers above are the contract, and
  a palette edit that drops `inkSecondary` under 4.5 on any of the four grounds
  is a regression even if it looks fine.
- Ten palettes ship (six dark, four light). `test/ink_contrast_test.dart`
  holds every one to the same gates and pins the default dark numbers above.
  Two roles that only split when the accent is bright: `accentText` is ink on
  a **solid accent** fill (dark on `midnight`/`deepSea`/`plum`/`graphite`/
  `ruby`), while ink on an `accentBg` chip is `accent` (5.40–12.82 across the
  ten). Ink on a solid `danger` fill is `dangerText` (white, 5.44 in every
  palette) — never `accentText`. The swipe drawer's action circles
  (2026-10-23) are solid fills and follow the same three inks: `dangerText`
  on `danger`, `accentText` on `accent`, `bg` on the cream `primary` —
  `SwipeAction.foreground` is required, so no call site can fall back to
  white on the cream disc.
- The planned chip (2026-10-23) is the same rule: `plannedText` (white) on a
  solid `plannedFill`, never `planned` on `plannedFill` and never
  `plannedText` on `plannedBg`. `plannedFill` is deeper than the palette's
  `planned` where the signal is a light blue, so white clears AA in every
  palette: 11.50 on `#1E3A5F` (dark, deepSea, plum, graphite, ruby — a muted
  navy a step off the row's `plannedBg` `#16253A`, so the chip reads as a
  value sitting in its row rather than a glowing box; a saturated fill read
  as exactly that, 2026-10-23), 5.17 on `#2563EB` (monoLight, blush), 5.70 on
  `#7C3AED` (midnight), 6.99 on `#7E22CE` (porcelain), 5.48 on `#0F766E`
  (sand). The chip's *edge* is the full
  `planned` tone, not the fill — the boundary against the planned row
  clears the 3:1 non-text bar, which the fill itself would not on any
  palette (fill vs row is only 1.34:1 in the navy; the edge is 4.52:1 on
  the fill and 6.07:1 on the row). Pinned per palette in
  `test/ink_contrast_test.dart`.

## 3. Ink roles

| Token | Means | Use for |
|---|---|---|
| `primary` | content | anything the user is reading, titles, values, labels |
| `inkSecondary` | **secondary text that must still be read** | dates, captions, counters, "WAS", gaps, eyebrows, quiet field labels |
| `muted` | decoration / disabled only | hairlines, dots, non-text glyphs, disabled chrome — **never a string the user reads** |

The split is the whole fix for the 2026-10-21 readability pass: before it,
"secondary" and "decoration" were one token, and the result was 3.04–3.87:1 on
informational text. When a label feels too loud, **size and weight** quiet it
first (typography §4); reach for `inkSecondary` before `muted`, and never
below `inkSecondary`.

## 4. Composites are grounds too

A translucent fill (`glassBox`, `chipBox`, a tinted row) is not the colour you
passed in — it is that colour **over** whatever sits behind it. The primary
glass over `surface` lands at `#403E3C`, and it moves a ratio by up to ~1.8
(`primary` 8.54 → 6.70) or down past the floor (`accent` 5.57 → 4.37). An ink
that passes on `surface` can fail on a glass panel drawn on a card, and one
that fails on glass can pass on the page.

- Measure the composite: alpha-blend the fill over its parent ground, then run
  the ratio.
- This is why `inkSecondary` was chosen to clear 4.5 on **every** ground the
  theme produces rather than only on the two flat ones — the rule can then be
  stated unconditionally instead of "safe except on glass".

## 5. Touch targets and semantics

- **40px minimum** for any interactive target; **44px** on a header
  (`HeaderIconButton` bare). The target may be larger than the glyph — spend
  the size inside the content (`compact: 10 + 20 glyph + 10`), never by
  stretching the container with an `alignment` (it fills loose constraints and
  drags a `MenuPopover` off screen).
- Every icon-only control carries `label: ''` + `icon` + `semanticsLabel` on
  `GlassButton`, or the equivalent on `HeaderIconButton`. The semantics label
  is both the screen-reader reading and the tooltip — write it as the action
  ("Add exercise note"), not the glyph ("plus").
- A mark that carries meaning (a completion check, a bullseye, a PR disc)
  states its words too — either a `Tooltip`/semantics label on the icon or an
  adjacent text label. Colour alone never carries state: a red row and a green
  row must differ in more than hue (text, icon, or label).
- Interactive rows are whole-row targets; do not shrink the tap area to the
  text run.

## 6. Disabled and loading states

- Disabled = 0.5 opacity of the same styling (`GlassButton.disabled`). It is
  exempt from contrast requirements, but disabled must never be the **only**
  way to learn a value — a disabled field still shows its value at full ink.
- Loading states keep the control's size (`GlassButton.loading`) so the layout
  never jumps when the result arrives.

## 7. Text scaling

- No `textScaler` handling exists in `lib/` as of 2026-10-21 — layouts rely on
  flexible boxes, not on fixed heights.
- Sheets and modals **must scroll** (never a fixed `Column` taller than its
  box), and headers wrap their title in a `Flexible`/`Expanded`.
- New surfaces are checked at **2.0** text scale before landing: no overflow
  stripes, no clipped values, the primary CTA still reachable.
- Fixed-height rows that hold text (set rows, tabs, chips) are the usual
  breakers; a value that must stay one line uses scale-to-fit (`FittedBox`)
  rather than an ellipsis on data.

## 8. Placeholders and the one absence glyph

Every **text placeholder** is `inkSecondary`: `LambdaInput`,
`LambdaSearchField`, `LambdaReadout`'s blank state, `DropdownSelect`'s
placeholder and empty/loading rows, and any ad-hoc "Select date" / "No
variations found" copy. Placeholders are read; they are not decoration
(2026-10-22).

The one deliberate exception is the numeric set-cell `—` (live and history
set rows, the exercise-target hint): it is an **absence glyph**, not a value
or a placeholder sentence, and it stays `muted` so an empty cell reads as
empty rather than as a logged zero. Tests that scan a whole surface for
readable ink pass `allowMuted: {'—'}` (see §9).

## 9. Checklist

- [ ] Every text ink is `primary` or `inkSecondary`; nothing informational is
      `muted`.
- [ ] The ratio was measured against the composite ground the text sits on.
- [ ] Icon-only controls have a semantics label and a ≥ 40px target.
- [ ] Meaning carried by colour has an icon or a word beside it.
- [ ] Disabled states keep their values readable.
- [ ] The surface survives text scale 2.0 — scrolls, wraps, no overflow.
- [ ] Text placeholders are `inkSecondary`; only the numeric `—` absence
      glyph is `muted` (§8).
- [ ] The surface is guarded by `expectReadableText` from
      `test/support/readable_text.dart`, which rejects full-opacity `muted`
      text and sizes below the 12px floor (alpha-muted disabled chrome is
      allowed; pass `allowMuted: {'—'}` where the absence glyph is drawn).
- [ ] `test/typography_guard_test.dart` still passes — no production
      numeric size below 12 and no tracking beyond 0.8.
