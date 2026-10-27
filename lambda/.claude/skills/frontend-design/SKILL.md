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

**Where the rules live — one owner per fact:**

| Fact | Owner |
|---|---|
| tokens, translucent recipes, containers, buttons, component inventory | this skill |
| the size ladder, families, weights, tracking, line height, size floors | **typography** |
| contrast ratios, ink roles, touch targets, semantics, text scaling | **accessibility** |
| how the three session screens stay identical | **session-ux-consistency** |
| what fits in a header bar | **header-text-limits** |
| inset alignment and centring | **spacing-and-alignment** |

If a rule you need is not here, follow the owner rather than inventing a new
value; if the owners disagree, the more specific one wins and the other is
repaired in the same change.

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
| `AppColors.primary` | ink | content — text and icons the user reads |
| `AppColors.inkSecondary` | secondary ink | text that must still be *read*, one step down: dates, captions, counters, quiet values. Clears AA on every ground and is the production default for secondary text since the 2026-10-22 rollout (**accessibility** §2) |
| `AppColors.muted` | dimmed | decoration, inactive icons, disabled chrome — **never text** (3.04–3.87:1 on the dark theme) |
| `AppColors.accent` + `accentBg` + `accentText` | brand (amber by default, per-theme) | PRs and PR-related highlights ONLY; `accentText` is ink on a **solid** accent fill, `accent` is the ink on an `accentBg` chip |
| `AppColors.planned` + `plannedBg` | blue | planned-session semantics ONLY — `planned` is the guide ink and the container's edge |
| `AppColors.plannedFill` + `plannedText` | muted navy + white (dark palettes) / the palette's own `planned` + white (light palettes) | the planned **value chip** (2026-10-23): ink on a solid fill — `plannedText` is white in every palette, the `dangerText` role, and clears AA on every `plannedFill` |
| `AppColors.success` + `successBg` | green | completion, Start/End CTAs |
| `AppColors.danger` + `dangerBg` + `dangerBorder` + `dangerText` | red | destructive/error ONLY; `dangerText` is ink on a solid `danger` fill |
| `AppSpacing` xs/sm/md/lg/xl/xxl | 4/8/12/16/24/32 | all gaps and padding |
| `AppRadius` md/lg | 8/12 | containers (pill = 999 inline) |
| `AppTextStyles` xs/caption/sm/body/md/lg/xl/xxl | 12/13/14/15/16/18/22/30 | the size ladder — owned by **typography** |
| `AppFonts.ui` / `AppFonts.mono` | `.SF Pro` on iOS (Manrope elsewhere); JetBrains Mono | text vs numbers/labels |

**Semantic color discipline:** accent = PR only; planned = planned only;
danger = destructive only. Never reuse a semantic color for decoration.
The note indicator uses `primary` glass for exactly this reason.

**Contrast is not chosen here.** Which ink to use on which ground is the
**accessibility** skill's measured table; this skill only says which token
means what.

## 2. Translucent recipes — exactly four (consolidated 2026-08-20)

Use `withAlpha(26)`/`withAlpha(77)` or `withValues(alpha: …)` on tokens.
Do NOT invent new alpha combinations.

1. **Glass** — `color.withAlpha(26)` fill + `color.withAlpha(77)` border.
   Buttons (GlassButton default), the active exercise pill, and the set-row
   note button. `primary` by default. **Its hollow half** —
   `glassBox(color, filled: false)`, the same `77` rim with the tint taken
   out — is a control that only reads (the star pill's read mode, 2026-10-28):
   one edge in both modes, the fill is the state.
2. **Chip** — `color.withValues(alpha: 0.1)` fill + `0.3` border.
   Pill buttons (Notes/History), program chips, wizard badges. `accent`
   normally, any semantic color is fine.
3. **Soft highlight (accent)** — solid state fill + `accent.withValues(
   alpha: 0.35)` border. PR count badges, pager arrows (accentBg fill),
   "+ ADD" rows, add-exercise rows (surfaceHigh fill).
4. **Soft highlight (planned)** — `plannedBg` fill + `planned.withValues(
   alpha: 0.35)` border. Planned badges, planned set rows, planned workout
   pills, the session selector's closed field. This is THE planned
   container; no other planned alphas exist (0.3/0.4/0.5 were folded into
   0.35).

**The planned grammar** (2026-10-23) is a three-state recipe, not a
container tone: a planned VALUE is a solid chip — `plannedFill` fill,
`plannedText` ink, `planned` edge (the full tone, not the fill, so the
boundary clears 3:1 on the planned row in every palette). In the dark
palettes the fill is a **muted navy a step off the row's `plannedBg` tint**
(2026-10-23 — a saturated fill read as a glowing box on the near-black
ground), so the chip is separated from its row by the `planned` edge, not
by the fill. Empty = the target as a `planned`-ink guide; matching real
value = the chip; off-plan value = plain cell. The variation cell is not a
guide cell: a planned variation is a **real value** — the plan's name in
`primary`, adopted by the row's first commit (2026-10-23). Session rows
only — never the planner or a record.

Solid state fills (`accentBg`, `plannedBg`, `successBg`, `dangerBg`) pair
with their full-color borders for banners and PR rows — those are the
"solid" tier, not alphas.

## 3. Typography system

**Two families, one split:** `AppFonts.ui` for everything human-readable;
`AppFonts.mono` for numbers, weights, reps, dates, IDs and uppercase
micro-labels. A sentence is never mono; a data value never ui.

**The ladder lives in typography** — the role table, the 12px floor, the
weights, tracking and line-height rules are all there. Do not restate sizes
here and do not pick a size by what fits; pick the role and take its rung.

**Micro-label recipe** (the app's signature, and the one recipe this skill
does own): `AppFonts.mono(fontSize: AppTextStyles.xs, fontWeight: w600,
letterSpacing: 0.8, color: AppColors.primary)` for uppercase section and
field labels. No production screen draws below this rung and no label tracks
past 0.8 — `test/typography_guard_test.dart` enforces both (2026-10-22).

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
- Fixed component sizes: set cells 38 high, icon buttons 40×40 (the
  session floor's bar controls 48×48 — `kSessionBarControlSize`, the
  undo/redo squares, the star and the stats tiles' height),
  chevron buttons 40×40, feeling stars 52, hairline 0.5–1px.
- Touch targets: 40px minimum (44 where height allows) — never below
  Apple's minimum tap size.

Vertical rhythm inside stacked cards (ReflectionSummary is the reference):
8 label→first block, 8 name→content, 16 between exercises, 24 between
sections.

This section is the *rhythm* only. Where a control's edge lands (a boxed
chip's inset, what "centred" means) is the **spacing-and-alignment** skill —
insets are measured from a control's box, and centered content centers on
the screen.

## 5. Button system — GlassButton for everything

One button widget: `GlassButton`. **Never** Material `FilledButton` /
`OutlinedButton` in app screens.

- Default = **glass recipe** (translucent tint + soft hairline), ink text.
- `solid: true` = full-tone fill, `bg`-colored text (danger uses dangerText).
- `color:` = semantic tone (`primary` default, `success` for Start/End,
  `danger` for destructive, `accent` sparingly).
- `compact: true` = size class ONLY (padding 14×10 vs 16×12) — orthogonal
  to everything; mixes freely: compact + solid + success, etc.
- `loading` / `disabled` = state flags; `icon` for icon buttons.
- Disabled = 0.5 opacity of the same styling.

**Glyph or word (2026-10-20).** A control is a **glyph** when it operates
the frame; it stays a **word** when it is the point of the screen.

- Glyph: header nav (back, close, edit, save/done), toolbar actions
  (add, archive, sort, filter), row actions (duplicate, delete, undo,
  redo, trash). They repeat on every screen; their meaning is carried by a
  platform-standard shape, not a noun.
- Word: primary CTAs (`Begin Program`, `Finish review`, `Save Note`),
  every dialog verb (`Cancel`/`Discard`/`Keep it`/`Delete review`),
  anything whose meaning depends on the word (`Notes`/`History`/`PRs`/
  `Compare`), pill labels carrying counts (`3 Notes`), filter chips
  whose text *is* the current value, and one-off actions (`Retry`,
  `Restore`, `Go to program`). A confirm's two options must stay readable —
  `Keep it` vs `Delete review` is the whole safety mechanism.
- **Dismissal ink (2026-10-22).** The way-out verb of a dialog (`Cancel`,
  `Stay`, `Keep`, `Discard`) is `inkSecondary` on a `TextButton`, or
  `primary` on a `GlassButton` (the lab's recipe) — quiet by weight, never
  by `muted`. The affirmative keeps `accent` (or `danger` for destructive).
- **A back-door warning has two verbs, never three (2026-10-23).** Leaving
  a screen with unsaved changes is a discard-or-stay decision:
  `UnsavedChangesGuard`'s dialog reads **Discard** (danger) / **Stay**
  (`inkSecondary`). Save is the screen's own button, not a third action on
  the way out — a warning that can write puts an accidental commit one tap
  from a back gesture. The one exception is `settleForReview`, which has no
  discard side (a review finishes on what is saved): there the pair is
  **Save and finish** (accent, w600) / **Stay**. Destructive confirms
  elsewhere keep their own pair (`Keep it` / `Delete review`) — the rule is
  two choices, not one vocabulary.
- Icon-only = `label: ''` + `icon` + **`semanticsLabel`**, which is both
  the screen reader's reading and the glyph's tooltip — one string, two
  audiences. A lone glyph stands on a ≥40px target, spent inside the
  content (compact: 10 + 20 + 10), never by stretching the container with
  an `alignment` — that fills loose constraints and drags a `MenuPopover`
  panel off-screen.
- Header controls use **`HeaderIconButton`** (`bare` = 44×44 target around
  an 18–20px glyph on a header; `boxed` = the glass square in a toolbar).
  Never a Material `IconButton`, never a text `GlassButton` standing in for
  a nav word.
- **One word control (2026-10-23).** The browse's **Resume** is the one
  word a session header carries: with a session live, the wizard's Home
  header swaps the Start glyph for a compact green `GlassButton` reading
  Resume — word only, no glyph beside it — because it is that page's
  primary CTA and the word is what differs it from Start (which would
  begin a second session). It returns to Training; never demote it to a
  glyph, and never give it one.
- **Header selector (2026-10-23).** When a header names a value the user
  can change, the value itself is the control: it stands in
  `PageHeader.titleWidget` as a **closed pill** — the current value in a
  ghost `lambdaBox` (`ContainerTone.planned` when the value is a plan),
  radius `md`, the value at 16 w600 `primary` on one ellipsized line,
  value at the start and `arrow_drop_down` 18 `muted` at the end (the
  selector field's own grammar), a 4pt gap between them. Tapping opens the
  menu or sheet that sets it. It is the title slot's control, never a body
  card and never a separate row. Two instances are one species: the exercise
  detail's `name · variation` (opens the variation menu) and the idle
  Training page's session template (opens the template picker sheet; an
  active session keeps the plain title, because a template cannot change
  mid-session). A selector standing as the page's **one** title control
  spends the whole band and stands 44 tall — the header's target height
  (`HeaderIconButton` bare) — so the bar reads as one row; the band is the
  control's ceiling, never bypassed (a switch riding a title, like the
  exercise detail's, hugs its value instead).

The set-row **note button** is a 40×40 square glass button (primary glass,
sticky-note icon) — the note indicator, not a color.

## 6. Container conventions

- Cards: `AppCard` (`surface` fill, `AppRadius.lg`, `border` hairline);
  pressable = `onTap`.
- **Flat session card (2026-10-22).** The session exercise card — the live
  Training page, the past-session viewer, the preview, and the planner
  (2026-10-26) — draws **no fill and
  no border of its own**; the page ground shows through and every control
  inside it carries its own chrome. It keeps the page's 16pt body padding
  and adds a 6pt inset inside itself, so the selector's chevrons, the set
  row's cells and ADD SET all land on the **22pt gutter** the session's
  caption/date bar uses: one vertical edge down the page. The card draws
  **no state rim at all** (2026-10-23): a planned exercise's blue is the
  selector's closed field (the planned container), the row's `plannedBg`
  tint and the value chips, so the plan reads off the values rather than
  around the furniture; a deleted exercise reads off its red selector name
  and red rows. Freestyle is completely flat. The planner is a session
  surface too since 2026-10-26 (it plans with the same card, floor and
  gutter), and a completed review's record joined them on 2026-10-27;
  only the pass's own workout editor keeps the boxed `AppCard`
  (`session-ux-consistency` §7, rule 9).
- Dense inner containers (rows, chips, inputs): `surfaceHigh` fill +
  `border` hairline + `AppRadius.md` (8).
- Banners: solid `*Bg` fill + full-color border + colored icon/text
  (success/planned/danger) — see the gallery.
- Section divider: centered mono-12 w600 primary label, 1px `border`
  hairlines left and right (the LAST/THIS SESSION divider).
- Reusable inputs: `LambdaInput` (label + placeholder + error + required +
  enabled + autofocus); `DropdownSelect` for pickers; `SegmentedControl`
  for toggles.
- **Text boxes — one rule, two halves (2026-10-07).** Every editable text
  box is `LambdaInput` — the Pre-Evaluation "Why do you feel that way"
  field is the reference: label above (ui sm w600 primary + 6px), a fill
  one tier above its ground (below), `border` hairline, radius 8, 16×14
  padding, md primary text, `inkSecondary` hint, accent focus. A dense search box
  is `LambdaSearchField`: the same chrome at toolbar scale (12×10 padding,
  sm text, optional magnifier, optional trailing control). Every read-only
  text box — text shown, not written — is `LambdaReadout` — **the field it
  stands in for with the fill taken out** (2026-10-28, the C · Hollow rule):
  the same label slot, then the field's own box — the outline border's
  content inset (**20 × 14**: the decoration's 16 plus the outline's 4pt
  gap, where `InputDecorator` seats the input), `border` hairline at radius
  8, md primary text at the field's weight, two lines at rest and six before
  the note scrolls inside — with a transparent fill. The box also reserves
  the field's hint height: an `InputDecorator` keeps `maintainHintSize` on
  even with a value in it, so a pair passes the field's `minLines` /
  `maxLines` **and** its placeholder (`fieldHint`) or a short note sits in
  a shorter box than its own field. Never hand-roll an `InputDecoration`,
  never park a block of text in a bare `Text`, and never style a read-only
  box as a disabled field.
  - **The ground rule (2026-10-08):** a box's fill is always one tier
    above what it stands on — `surface` on the page ground (the reference
    look), `surfaceHigh` on a `surface` ground (a card, a default modal
    sheet, the variation picker): pass `elevated: true` on `LambdaInput`
    or `LambdaSearchField`. A box whose fill matches its ground reads as
    dead text, however editable it actually is.
  - **Exceptions:** an inline header title that IS the header (tap-to-
    rename, chrome-less, centred — the program and workout name fields);
    numeric cells (set grid, target pickers — mono, centred, their own
    family); the exercise card's review note box, which copies the
    session-prep reference field by name — base `surface` fill, no step
    up, the card's hairline carrying it (2026-10-08).
  - **Dismissal is the frame's job (2026-10-20):** a tap on empty space
    unfocuses wherever a field is up — `KeyboardDismissOnTap`, wired once
    in `lib/app.dart`. No field carries its own `onTapOutside`: a
    per-field callback fires on pointer down (the field takes focus on
    pointer up), so it blinks the keyboard when the user moves between
    adjacent cells.
  - **Read vs edit is one box (2026-10-28).** The study under Dev → Visual
    Pairings (`/dev/visual-pairings`) picked **C · Hollow** and it shipped
    the same day: a control's mode is its **fill** — filled = it takes
    input, hollow = it only reads — and the edge never moves. `LambdaReadout`
    is `LambdaInput` hollowed (one geometry, so a toggle moves no words, not
    even the size), and `FeelingRating` wears the rule as one pill —
    `glassBox(primary, radius: 999)` while interactive,
    `glassBox(..., filled: false)` while read-only. `framed: false` is only
    the 14px pre/post stars inside a log card: the row is a glance, not a
    control. Because the readout is always the field's shape, a read/edit
    pair passes the field's `minLines` / `maxLines`, never a type size.

### User-created names (2026-10-20)

Any string the user types as an identifier — exercise, variation, workout,
program, block, goal, review title — draws through **`UserNameText`**: one
line, `TextOverflow.ellipsis`, `tooltip: true` where the name is the thing
being *chosen*, and an `Expanded`/`Flexible` around it whenever it shares a
`Row` (an ellipsis cannot engage without a bound; `overflow` alone with no
`maxLines` never engages at all). Notes, lesson bodies and goal descriptions
are prose: they wrap and stay unbounded.

Names are stopped at the field, in this order — all four, because each one
alone has a hole:

1. `LambdaInput.maxLength` (or the header `TextField`) with the kind's
   `kMax*NameLength` from `lib/core/utils/name_limit.dart`, plus a
   `NameLimitCounter(length:, max:)` under it.
2. Save gated on `!nameTooLong(value, max)` — an over-long name must never
   offer a Save that silently no-ops.
3. The viewmodel states the refusal (`nameTooLongMessage(max)`) instead of
   returning silently; a modal stays open to show it.
4. The repository throws `ArgumentError.value` at the write
   (`_assertNameFits`, mirroring `ExerciseRepository`).

**Every cap is 20 (2026-10-20).** One budget for every kind — exercise,
variation, workout, program, block, goal text, review title — because the
number is measured from the **narrowest surface a name is drawn on**: the
`PageHeader` title (88pt gutters each side → 217–226pt of a phone header, ~20
average characters at `AppTextStyles.lg` w600). A wider cap is a name the app
has to cut where it matters most — the session a workout is named for, the
program's own header, the review you opened. Cards, banners and list rows are
wider and fit twenty comfortably, so the header is the number, not the card.
If a kind ever earns a longer budget, it earns it by being drawn somewhere
wider than a header title — never by "it seemed short". The measurement, the
rule for authored titles, and the checklist live in the **header-text-limits**
skill; read it before writing anything that lands in a header bar.

A row already over the cap is **grandfathered** at the repository: the
workout discard path writes back the name the row was opened with, and a rule
that arrived after the row must not block its rollback. The field still caps
every edit the user can make, so a grandfathered row shrinks the first time
the name is touched.

**Generated copy names are the one deliberate exception.** A duplicate is
`'<source> (Copy)'` / `'<source> (Copy 2)'` (`uniqueName`) — a name the user
did not type, inserted by a copy path that never passes through a field. It
may exceed the cap; the ellipsis covers it, and the field trims it the first
time the copy is renamed. The cap governs typed names, not suffixes.

The database rail is 120 for all five wider kinds
(`20261020120000_name_length_rails.sql`) — deliberately above every
client cap, because the PowerSync mirror is a plain `Column.text` with no
CHECK: a write the app can trip would land locally and then quarantine
server-side (23514), the device and server silently disagreeing. The rail
catches a future client that forgets the rule; it is not the enforcement.

## 7. Shared component inventory (`lib/shared/widgets/`)

PageHeader, GlassButton, HeaderIconButton, BarIconButton (the 48pt square
floor-bar control, 24px glyph — the nav bar's icon size, the PR Lab's
recipe; `compact` draws the 32 header species; `UndoRedoButtons` is two of
them), InfoButton, AppCard,
LambdaInput + LambdaReadout + LambdaSearchField (the text-box trio — §6),
KeyboardDismissOnTap + KeyboardDismissOnScroll (dismissal — §6, wired once
at the app root and per-screen respectively),
NameLimitCounter, UserNameText, ExercisePillBar + ExerciseTabChip,
StatsRow/StatsTile, SwipeActions/SwipeAction, FeelingRating,
SegmentedControl, DropdownSelect, SlidePages, ReflectionSummary, MenuPopover
(+ SortButton/FilterButton), FloatingBar, SessionExerciseCard/SessionSetRow,
SessionDateBar, SessionBookend, LogsFilterBar. Anything appearing on 2+ screens
belongs here, never copied per-screen (session-ux-consistency governs the
three session surfaces specifically).

**The swipe drawer (2026-10-23).** `SwipeActions`/`SwipeAction` is the app's
one swipe-to-reveal drawer, promoted from the PR Lab. Each action is a
**filled circle** floating in a 52pt slot (`_slotWidth`) on the page's own
ground; the circle is the row's height minus 8, capped at 40 and floored at
16, and the glyph is half the circle (a 52-tall row draws a 40 disc with a
20 glyph, centres 12 apart). The glyph's ink is `SwipeAction.foreground` —
`dangerText` on `danger`, `accentText` on `accent`, `bg` on the cream
`primary` — never plain white, which disappears into `primary`. Nothing
fades: the drawer paints at full strength and each circle scales from zero
with `easeOutCubic` as its own slot is uncovered, the trailing action
arriving first; the opaque card in front is what hides a resting action
(`Transform.scale`, never `Opacity`). One drawer is open app-wide (a static
slot inside the widget), and while one is open a **tap** anywhere off its
action circles closes it — a tap is a pointer that went down and up without
travelling past `kTouchSlop`, so the drag that opened the drawer never trips
it. Release past 50 % or a flick past 300px/s snaps open; otherwise it
closes; a tap on the card closes it once open; a tap on a circle closes the
drawer and fires the action. The clip radius must be the child's own
(`AppRadius.md` for set rows and goal cards, the `AppRadius.lg` default
otherwise) — a larger radius shaves a child's rounded border down to its
straight runs.

**The floor-bar stat door (2026-10-22; the three-door bar 2026-10-27).**
`SessionStatsTiles` (`features/session/view/session_stats_bar.dart`) is the
session floor's three doors — trophy (PRs), goals bullseye and note glyph
(exercise notes), each a third of the row's inner slot and a
48-tall glass control (`kSessionBarControlSize`, the undo/redo boxes' own
height) with a 24px glyph — **a glyph alone: no door draws a count**
(2026-10-27), the feeds' sizes riding only the semantics. **A door is
neutral until it has something to say**
(2026-10-27): `primary` glass and ink while its feed is empty, the
**accent** glass and ink once it is not — the trophy when the session
gained PRs (the whole shelf on the planner), the bullseye when open goals
stand, the note when this session carries exercise notes. **The count never
decides whether the control is a door** (2026-10-23): the PR Lab's own bar
always taps, and the sheets hold the exercise's whole story, not only this
session's additions — so a `0` still opens. The quiet control (`surfaceHigh`
+ hairline, primary ink, no tap) is only the no-exercise fallback. The whole
control is one semantics node (`"2 PRs this session"`), so the number never
arrives without its meaning. The count is the **active exercise's** gain in
the session on screen — not the session's total — and the doors are the PR
Lab's sheets (2026-10-22): the trophy opens `showPrHistorySheet`
(`features/session/view/pr_history_sheet.dart`), the exercise's whole PR
feed filtered by WEIGHT / REPS / VARIATION and read chronologically
newest first (2026-10-23): `AFTER` at the top, drawn only
when non-empty (the caller passes the session's start), then the
session's own shelf split on its set ids — headed `THIS SESSION` on the
live page, or by the record's date (`20 OCT 2026`) when it is a past
record — then `PREVIOUSLY`, so a record read from Logs never files a
later PR under "previously"; the note glyph opens the grouped exercise-notes modal
(`sessionId` / `sessionStartedAt` / `sessionIsLive` = the same session),
which stands the same three shelves with its own drawn by `sessionId`.
Both follow the date bar, so a walk moves the doors with the sets. **The
bullseye stands between them** (2026-10-26; a numbered door since
2026-10-27), drawn only when the surface passes `onGoalTap` — the live
page, the viewer and the planner / review workout editor carry it
(star · trophy · bullseye · note); a friend's or athlete's record does not.
It opens `showExerciseGoalsSheet`
(`features/goals/view/exercise_goals_sheet.dart`) on the PR sheet's
furniture — the exercise's goals, Open by default behind a status control,
ordered by `SortButton`, a met goal in success ink — and a PR whose set
achieved a goal draws **success** instead of accent in the trophy's own
sheet (the same `goalSetIds`). The
old `PRs Achieved` modal and the per-exercise breakdown sheets are gone. The live session and the past-session viewer draw
the same doors beside the same star (`BarIconButton`, `star_rounded`,
"Session ratings", **primary** glass — neutral like the undo/redo pair;
the star never takes the accent, 2026-10-27).

**The pinned-note reader (2026-10-23).** The card's pinned-note bar opens
`showPinnedNotePopup` (`features/session/view/pinned_note_popup.dart`)
instead of jumping into the notes sheet: an `AlertDialog`
(`backgroundColor: AppColors.surface`) titled **Exercise Note**, the whole
note at `AppTextStyles.body` / height 1.35 inside a
`SingleChildScrollView` (notes are uncapped prose), and two verbs — `Close`
(`inkSecondary`) and the accent **View all exercise notes**, which
dismisses the reader and opens the sheet. Close, the barrier and the back
gesture only read; a surface with no sheet behind it still shows the
reader and withholds only that door. The bar's marker glyph is the set
row's own `Icons.sticky_note_2_outlined` — **one note glyph everywhere**
(the floor tile, the Notes pill, the pinned bar, the recap's EXERCISE
NOTES label); the **pin** (`Icons.push_pin`, accent when pinned) survives
only inside the notes sheet, where it is a pin/unpin control, not a
marker.

**The floor-bar date bar (2026-10-22).** `SessionDateBar`
(`shared/widgets/session_date_bar.dart`) leads the floor, above the action
row, on both session surfaces. It is a `ghost` box at `AppRadius.md` with a
5pt inset, holding one centred `FittedBox` phrase between two
`SessionChevronButton`s: the state (`TODAY -` in accent while the session
being logged is today's, `PREVIOUSLY -` in `inkSecondary` while a record is
read — mono caption, w700, tracking 0.8) and the date (`d MMM yyyy`, mono
caption, tracking 0.6, primary ink). **Tapping the phrase cycles its
reading** (2026-10-23): the written date, `N days ago`, `N weeks N days
ago`, then round again — a relative reading drops the `PREVIOUSLY -`
phrase (it says the same thing twice), and a session under a week has no
weeks reading, so its cycle is date ↔ days. The old reading is cut away
and the new one scales in (0.85→1, 180ms, ease-out), because the bar is a
readout, not a destination; a live session's phrase is inert — today is
today in every reading, so it is not a control. The row is `SessionChevronButton.
kSessionChevronSize` (40) high — the lab's own pager row. **A radio pair
rides inside the bar (2026-10-23).** The arrows walk one of two stacks —
EXERCISE (the active exercise's own performances, the default on both
surfaces) or SESSION (whole records) — and both are always visible side by
side on a row under the date, inside the same ghost box (which grows to
hold both rows; the chevrons keep their 40), centred, exactly one checked:
`SESSION` left, `SESSION BY EXERCISE` right — the labels name what the
arrows walk: whole records, or the active exercise through its own
performances (the default). Discreet by
design — no glass, no fill and no second surface: a 14px
`radio_button_checked` / `radio_button_unchecked` glyph (accent / muted)
then 4pt then the word in the date's own mono caption (`AppTextStyles.
caption`, tracking 0.6), `primary` ink when checked and `inkSecondary`
when not. Each option keeps a 40pt target even though the text is the
date's size, and only the unchecked side is a switch — tapping the live
side does nothing. Semantics: one node per radio, mutually exclusive
group, checked state, "Session" / "Session by exercise" plus a hint naming
the walk; without a toggle callback the bar draws no radios, so a
single-stack bar has no dead control. The phrase keeps its whole
width between the arrows and centres there. **The chevrons
walk the live stack** (2026-10-22, the lab's pager carried over): older
on the left, newer on the right, one recipe with the selector's flanks so
the two pairs never read as two sizes of the same control, their
semantics naming the stack (`Previous/Next performance` or `Previous/Next
session`). The bar only
takes the two callbacks; the stage decides what a step means. A step is
**in place** — the page stays mounted and the record's sets swap under it,
exactly like the lab's pager. Both session surfaces step in place: the live
Training page hosts the record itself (`SessionHistoryPeek`, the viewer's
own body), so even its step onto "today" is only the live sets coming back,
and the /logs route's step onto today is its one real move (a pop when the
route was pushed from live, else the session tab). A null
callback greys that arrow rather than removing it — the phrase keeps the
bar's middle, and a dead end stays a hole in neither the layout nor the hit
test. `glassBox(AppColors.primary)` when live, transparent hairline +
`muted` glyph when spent.

**The browse filter bar (2026-10-23).** `LogsFilterBar`
(`shared/widgets/logs_filter_bar.dart`) is the Sessions browse's chips,
one widget shared by the Session tab's Home and the logs list: **two rows
of two** — exercise · variation over workout · date — because four 44-tall
chips with 14px labels do not fit one 402pt line. Each chip is the glass
recipe at 44 tall (active in `accent`, inactive in `primary`), the value
ellipsized on one line with a 14px `keyboard_arrow_down`. The unfiltered
labels are the nouns (`Exercise`, `Variation`, `Workout`); a set filter
shows its value instead. The workout chip lists the planned sessions found
in the list, keyed by `planned_session_id` and labelled with the name
their sessions snapshot, so a template rename keeps old logs under one
group. The unfiltered date range reads **`All time`** (the shared
`DateRangeSelection.label`). The clear X (18px `muted` glyph) rides at the
end of the second row and exists only while some filter is set. Each chip's
picker sheet names its own kind — `Choose exercise` / `Search exercises…`,
`Choose workout` / `Search workouts…` — through
`showDropdownPickerSheet`'s `title` / `searchHint` / `emptyLabel`, whose
defaults stay the variation copy the set rows use; a sheet that reads
"variation" over a workout list is the chip's bug, not the picker's.

## 8. Rules for new UI

1. Tokens only — no raw colors/sizes; new colors go through
   `LambdaColors`/`LambdaTheme`. Every palette lives in
   `LambdaThemeVariant` (six dark, four light) with its label and
   description in the same catalog, so Profile → Appearance lists it
   automatically and the dev Experimental screen cannot fall behind.
2. Pick a recipe from §2 — never a fresh alpha.
3. Numbers, dates, stats, uppercase labels → mono; everything else → ui.
4. New interactive controls → GlassButton/DropdownSelect, not ad-hoc
   Material widgets; text boxes follow §6's rule (editable →
   LambdaInput/LambdaSearchField, read-only → LambdaReadout).
5. Spacing from §4; when unsure, sm=8 between label and content, lg=16
   between cards, xl=24 between sections.
6. Add the new component to the Style Gallery so it stays discoverable.
7. Ink by role, never by opacity (2026-10-22): content `primary`,
   secondary text that must be read `inkSecondary`, `muted` only for
   decoration/disabled chrome. Text placeholders are `inkSecondary`; the
   numeric set-cell `—` is the single muted absence glyph
   (**accessibility** §3, §8). Hierarchy comes from size and weight.
