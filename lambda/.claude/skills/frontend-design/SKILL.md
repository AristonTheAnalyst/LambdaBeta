---
name: frontend-design
description: >
  Lambda's front-end design system — tokens, translucent recipes, typography
  and spacing rules, the button system, and container conventions. Use when
  building or restyling ANY UI in this app (new screens, widgets, modals,
  tiles, banners) so new work matches the existing design language instead
  of inventing new colors, sizes, or treatments.
---

# Lambda Front-End Design System

The dev-tab **Style Gallery** (`lib/features/dev/view/gallery_screen.dart`)
is the living catalog of everything below — check it after changes. The
**session-ux-consistency** skill governs how the three session surfaces stay
identical; this skill governs how EVERYTHING looks.

## 1. Design tokens — never use raw values

All styling goes through `lib/core/styles/` tokens. No literal hex colors,
raw font sizes, or magic paddings in widgets.

| Token | Value | Purpose |
|---|---|---|
| `AppColors.bg` | page background | scaffold ground |
| `AppColors.surface` | card fill | cards, sheets |
| `AppColors.surfaceHigh` | elevated fill | rows, chips, inputs inside cards |
| `AppColors.surfaceLow` | recessed fill | containers darker than the page ground (e.g. the all-sessions picker rows) |
| `AppColors.border` | hairline | all borders |
| `AppColors.primary` | ink | text, icons, neutral emphasis |
| `AppColors.muted` | dimmed | secondary text, inactive icons |
| `AppColors.accent` + `accentBg` + `accentText` | orange | PRs and PR-related highlights ONLY |
| `AppColors.planned` + `plannedBg` | blue | planned-session semantics ONLY |
| `AppColors.success` + `successBg` | green | completion, Start/End CTAs |
| `AppColors.danger` + `dangerBg` + `dangerBorder` | red | destructive/error ONLY |
| `AppSpacing` xs/sm/md/lg/xl/xxl | 4/8/12/16/24/32 | all gaps and padding |
| `AppRadius` md/lg | 8/12 | containers (pill = 999 inline) |
| `AppTextStyles` xs…xxl | 11/13/15/17/20/28 | body ladder |
| `AppFonts.ui` / `AppFonts.mono` | SF Pro (iOS) / Manrope; JetBrains Mono | text vs numbers/labels |

**Semantic color discipline:** accent = PR only; planned = planned only;
danger = destructive only. Never reuse a semantic color for decoration.
The note indicator uses `primary` glass for exactly this reason.

## 2. Translucent recipes — exactly four (consolidated 2026-08-20)

Use `withAlpha(26)`/`withAlpha(77)` or `withValues(alpha: …)` on tokens.
Do NOT invent new alpha combinations.

1. **Glass** — `color.withAlpha(26)` fill + `color.withAlpha(77)` border.
   Buttons (GlassButton default), the selected feeling square, the active
   exercise pill, and the set-row note button. `primary` by default.
2. **Chip** — `color.withValues(alpha: 0.1)` fill + `0.3` border.
   Pill buttons (History/Lessons), program chips, wizard badges. `accent`
   normally, any semantic color is fine.
3. **Soft highlight (accent)** — solid state fill + `accent.withValues(
   alpha: 0.35)` border. PR count badges, pager arrows (accentBg fill),
   "+ ADD" rows, add-exercise rows (surfaceHigh fill).
4. **Soft highlight (planned)** — `plannedBg` fill + `planned.withValues(
   alpha: 0.35)` border. Planned badges, planned set rows, planned workout
   pills, ghost target cells. This is THE planned container; no other
   planned alphas exist (0.3/0.4/0.5 were folded into 0.35).

Solid state fills (`accentBg`, `plannedBg`, `successBg`, `dangerBg`) pair
with their full-color borders for banners and PR rows — those are the
"solid" tier, not alphas.

## 3. Typography system

**Two families:** `AppFonts.ui` (295 uses) for everything human-readable;
`AppFonts.mono` (109 uses) for numbers, dates, and uppercase micro-labels.

**The size ladder (by role, from actual usage distribution):**

| Size | Family | Role |
|---|---|---|
| 10 | mono, ls 0.6–0.8 | column labels, stat labels, PR badge |
| 11 | mono, ls 0.8 | section labels (PRE-WORKOUT, SETS…), badges, dates |
| 12 | mono, ls 0.6 | planned labels, small badges |
| 13 | ui / mono | small body + muted notes; set numbers |
| 14 | ui / mono | button-adjacent labels, PR lines (mono, w700) |
| 15 | ui, w600 | questions, field labels, notes text — the workhorse body size |
| 16 | ui | input text, list rows, modal body |
| 17 | ui / mono | set-cell input text (mono w500), body md |
| 19 | ui, w800 | modal titles; stat VALUES (mono w500) |
| 20 | ui, w800 | screen/page titles, exercise names |
| 22/30 | ui, w800 | display headings (sparingly) |
| 32/64 | mono | statistics display numbers |

**Weights:** w600 (96×) labels/buttons/questions; w800 (59×) headings;
w700 (32×) strong emphasis; w500 (16×) numeric input text; w400 rare (body).

**Micro-label recipe** (the app's signature): `AppFonts.mono(fontSize: 11,
letterSpacing: 0.8, color: AppColors.muted)` for uppercase section labels;
10px + ls 0.6 for inside-card column labels.

## 4. Spacing system

**Always tokens** — `AppSpacing.sm` (8) is the most-used gap. Observed
rhythm, in priority order:

- Page content padding: `lg` (16) on every screen body.
- Card padding: 16 default (AppCard), `md` (12) for dense content cards.
- `sm` (8): label → content, icon gaps, chip gaps.
- `lg` (16): between cards / related blocks.
- `xl` (24): between top-level sections.
- `xxl` (32): page-end / large separators.
- `xs` (4): micro-gaps (icon–label inside chips).
- 6px: label → field (inputs), row gaps in grids (set rows).
- Fixed component sizes: set cells 38 high, icon buttons 40×40,
  chevron buttons 40×40, feeling stars 52, hairline 0.5–1px.
- Touch targets: 40px minimum (44 where height allows) — never below
  Apple's minimum tap size.

Vertical rhythm inside stacked cards (ReflectionSummary is the reference):
8 label→first block, 8 name→content, 16 between exercises, 24 between
sections.

## 5. Button system — GlassButton for everything

One button widget: `GlassButton`. **Never** Material `FilledButton` /
`OutlinedButton` in app screens.

- Default = **glass recipe** (translucent tint + soft hairline), ink text.
- `solid: true` = full-tone fill, `bg`-colored text (danger uses accentText).
- `color:` = semantic tone (`primary` default, `success` for Start/End,
  `danger` for destructive, `accent` sparingly).
- `compact: true` = size class ONLY (padding 14×10 vs 16×12) — orthogonal
  to everything; mixes freely: compact + solid + success, etc.
- `loading` / `disabled` = state flags; `icon` for icon buttons.
- Disabled = 0.5 opacity of the same styling.

The set-row **note button** is a 40×40 square glass button (primary glass,
sticky-note icon) — the note indicator, not a color.

## 6. Container conventions

- Cards: `AppCard` (`surface` fill, `AppRadius.lg`, `border` hairline);
  pressable = `onTap`.
- Dense inner containers (rows, chips, inputs): `surfaceHigh` fill +
  `border` hairline + `AppRadius.md` (8).
- Banners: solid `*Bg` fill + full-color border + colored icon/text
  (success/planned/danger) — see the gallery.
- Section divider: centered mono-12 w700 primary label, 1px `border`
  hairlines left and right (the LAST/THIS SESSION divider).
- Reusable inputs: `LambdaInput` (label + placeholder + error + required +
  enabled); `DropdownSelect` for pickers; `SegmentedControl` for toggles.

## 7. Shared component inventory (`lib/shared/widgets/`)

PageHeader, GlassButton, AppCard, LambdaInput, ExercisePillBar +
ExerciseTabChip, StatsRow/StatsTile, SwipeActions/SwipeAction,
FeelingRating, SegmentedControl, DropdownSelect, SlidePages,
ReflectionSummary. Anything appearing on 2+ screens belongs here, never
copied per-screen (session-ux-consistency governs the three session
surfaces specifically).

## 8. Rules for new UI

1. Tokens only — no raw colors/sizes; new colors go through
   `LambdaColors`/`LambdaTheme` and both variants (dark primary /
   monoLight).
2. Pick a recipe from §2 — never a fresh alpha.
3. Numbers, dates, stats, uppercase labels → mono; everything else → ui.
4. New interactive controls → GlassButton/LambdaInput/DropdownSelect,
   not ad-hoc Material widgets.
5. Spacing from §4; when unsure, sm=8 between label and content, lg=16
   between cards, xl=24 between sections.
6. Add the new component to the Style Gallery so it stays discoverable.
