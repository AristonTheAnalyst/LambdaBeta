---
name: session-ux-consistency
description: >
  UX consistency rules for Lambda's three session surfaces. Use when
  changing any session UI — the live session screen, the past-session
  viewer (logs), or the planner — to keep them one shared UX instead of
  three divergent copies, while still allowing context-specific features.
---

# Session UX Consistency — One UX, Three Contexts

## The principle

A user looking at a session — **logging it now**, **reviewing it later**,
or **planning it ahead** — is looking at the same thing. The layout,
styling, gestures, colors, and component behavior must be **identical**
across all three screens. There is exactly ONE implementation of each
shared piece of UX; context differences are expressed as parameters, not
as copied code.

The user's words: *"it needs to have only a singular UX rather than it
being defined 3 times… but there still needs to be a way of implementing
unique functions or viewing experiences depending on the context."*

## The three screens

| Screen | File | Context |
|---|---|---|
| Live session | `lib/features/session/view/session_screen.dart` | Logging right now (mutable facts) |
| Past-session viewer | `lib/features/logs/view/session_detail_screen.dart` | Reviewing history (view/edit modes) |
| Planner | `lib/features/programs/view/plan_session_screen.dart` | Editing a template (dim) |

## Vocabulary (so we all mean the same thing)

- **Tab bar / pill bar** — the horizontal row of exercise chips under the
  stats bar (tap to switch exercise). Rendered by `ExercisePillBar`.
- **Set row** — one KG/REPS/VARIATION/NOTE grid row inside an exercise card.
- **Ghost target** — the planned-target hint behind a weight/reps cell in
  the live session (shows the planned target while typing).
- **Planned style / planned container** — the user-defined term for any
  container representing something planned: a `planned` border at 0.35
  alpha (unified from 0.3/0.4/0.5 on 2026-08-20).
  Banners may also use the `plannedBg` fill, but cards keep their normal
  surface background — the fill was tried on exercise cards and reverted.
  Use this outline for ALL planned things.

## The golden rules

1. **Shared UI lives in `lib/shared/widgets/`.** If the same component
   appears on 2+ of the three screens, it MUST be a shared widget with
   params — never a third copy.
2. **Visual styling is never context-specific.** Colors (active states,
   accents, PR highlighting, conditional colors), row backgrounds/borders,
   text styles, gestures, and affordances are identical across all three
   screens. If a color means something in one screen, it means the same
   thing in all of them.
3. **Differences are content or capability, not styling:**
   - Content: the past-session viewer shows pre-workout feeling; the live
     screen doesn't (no stored value yet). That's fine.
   - Capability: edit-mode-only buttons (add/reorder in the past-session
     viewer, day-of-week picker in calendar planner) are fine — they're
     *present or absent per mode*, not *styled differently*.
4. **When in doubt, unify.** If you're not sure whether something is a
   legitimate context difference, it probably isn't. Make it shared and
   gate it with a param (e.g. `onAdd`, `onReorder`, `onRemove` being
   nullable, `readOnly`).

## Current shared inventory (already unified)

| Component | Where | Notes |
|---|---|---|
| `ExerciseSelector` | `shared/widgets/exercise_selector.dart` | The pill bar + popover, embedded in the shared card — the only exercise-tab UI since 2026-08-23 (`ExercisePillBar` deleted). |
| `ExerciseTabChip` | `shared/widgets/exercise_tab_chip.dart` | The pill itself. Active color is accent everywhere — do NOT pass per-screen `activeColor` again (the planner's green was removed on purpose). |
| `SwipeActions` | `shared/widgets/swipe_actions.dart` | Duplicate/Delete drawers. No visual affordance at rest — the swipe gesture is the discovery mechanism. |
| `StatsRow` / `StatsTile` | `shared/widgets/stats_row.dart` | Stats bar tiles; PR tile is tappable when > 0. |
| `lessons_modal.dart`, `notes_modal.dart` | `features/session/view/` | Shared modals (lessons modal is polymorphic: takes a Listenable + callbacks). |
| `DropdownSelect` | `shared/widgets/dropdown_select.dart` | Variation picker; `valueColor` default primary everywhere. |
| `SessionSetRow` | `shared/widgets/session_set_row.dart` | THE one set row (unified 2026-08-22). `SetRowMode { live, planned, history }` derives per-context behavior (formatter, ghost/highlight tint, draft materialization, duplicate guard); orthogonal state is flags (`isPr`, `readOnly`, `plannedTarget`, edit-gate `editConfirmed`/`onEditConfirm`). All VM work goes through bridge callbacks (`onCommit`, `onVariationChanged`, `onNotesSave`, `onDelete`, `onDuplicate`, variation trio). Since 2026-10-13 `onCommit` carries an `immediate` flag — keystroke commits are false (debounce-eligible, merged by the VM into one write per settle), blur and the registered flush handle are true (write now, the no-data-loss safety net); the planner ignores the flag. The file also owns `recordSetRow`, the one **read-only** row builder — a record is read by two readers (the Compare flip, the record's workout screen) and they must not drift. |
| `SessionExerciseCard` | `shared/widgets/session_exercise_card.dart` | THE one exercise card (unified 2026-08-22). Selector, pinned lesson, Lessons/History/PRs pills, sets grid, history picker/detail. Screens adapt VM state into plain inputs; **null callbacks grey the control** (null `onLessonsTap` → greyed pill, null `onAdd` → greyed Add Exercise, null `onRemoveRequest` → the modal's tick goes informational, null `onAddSet` → no ADD SET, null `history` → History pill greyed). The history detail is the same sets grid (headers + `SessionSetRow`s in `history` mode): the live screen passes edit-gated rows (tap any field → one-time "edit past data" confirm; never swipe actions), the logs screen passes `readOnly: true` rows. |
| `CardPillButton` | `shared/widgets/card_pill_button.dart` | The pill chrome inside the card. |
| `ExerciseSelector` | `shared/widgets/exercise_selector.dart` | Field + anchored popover; `onMove`/`onAdd` are nullable (null greys reorder arrows, greys Add row). Owns `ExerciseMark` — the green **plus** / red **minus** (a filled disc, `Icons.add_circle`/`remove_circle`: a bare stroke at 14px read as a hyphen or a smudge — 2026-10-12) a review's exercise names wear (`marks`, parallel to `exercises`; empty everywhere else, a null entry or a list that stops short leaves that name bare). The mark rides beside the name in the field and in every popover row, so the name ellipsizes left of it. |
| `AddExerciseModal` | `shared/widgets/add_exercise_modal.dart` | THE add-exercise picker (`showAddExerciseModal`), one copy for all three screens since 2026-09-29 — replacing the three copy-pasted `_AddExerciseContent`s and the hold-to-delete X. Stay-open multi-select: tap to add, tap a ticked row to remove (the screen owns the confirm dialog), `+ Create` adds without popping. |
| `SessionBookend` | `shared/widgets/session_bookend.dart` | One pre/post questionnaire section — the prep page's LAST SESSION card and the past-session viewer's Summary tab. Null callbacks keep it read-only; non-null make stars/notes editable. |
| `LambdaInput` / `LambdaReadout` / `LambdaSearchField` | `shared/widgets/` | The text-box rule (2026-10-07): EVERY editable box is `LambdaInput` (dense search boxes: `LambdaSearchField`), EVERY read-only box is `LambdaReadout`. The note modals, the bookend and the exercise card's review note all wear them, so text looks the same wherever it is read. A box's fill is one tier above its ground — `surface` on the page, `surfaceHigh` on a card or default sheet (`elevated: true`; 2026-10-08) — with one named exception: the exercise card's review note box copies the session-prep reference field exactly (base fill, no step up; 2026-10-08). Full rule: frontend-design §6. |

## Per-screen adapters (thin shells — do not add card/row chrome here)

The three screens own only their shells (headers, wizard, stats-bar
placement, footers) and a private adapter that maps their VM into
`SessionExerciseCard`/`SessionSetRow`:

- `lib/features/session/view/live_exercise_card.dart` — `LiveExerciseCard` (SessionViewModel).
- `lib/features/programs/view/plan_session_screen.dart` — `_PlanExerciseCard` (ProgramDetailViewModel; pills greyed by decision).
- `lib/features/logs/view/session_detail_screen.dart` — `_DetailCardBuilder` (SessionDetailViewModel; edit-mode flags gate the callbacks).
- `lib/features/programs/view/record_workout_screen.dart` — a **reading**, not a fourth editor (2026-10-12): a completed review's two frozen sides of one workout — `baseline_content` (as the pass found it) and `snapshot_content` (as it completed) — wearing the pass's own chrome, `ReviewBar` included, via `reviewChrome(context, session:, readOnly: true, loadComparison:)`. It adapts plain `ContentExercise`/`ContentSet` rows — no VM — and is the shape every other read-only surface should copy: `onMove`/`onAdd`/`onAddSet`/`onLessonsTap`/`onPrTap` null (the controls grey or are not drawn), rows via `recordSetRow` (see above), `reviewNote` with a null `onReviewNoteChanged`. It is also the only surface that pairs a mark with a minus: showing the record's own side an exercise the baseline did not hold wears `ExerciseMark.added`; showing the baseline one the record does not hold wears `ExerciseMark.removed` (a live pass, whose tabs are always the plan's, shows the plus alone). Switching exercises stays — looking is not writing — and the eye swaps which side is drawn. On a record the bar's verbs wear what the record says rather than writing it: the tick is drawn green and disabled, the note glyph greyed, and the label names the frozen side on screen (`kReviewAfterLabel` / `kReviewBeforeLabel`, green turning accent as the eye turns) rather than the walk a pass's label reports.

Any change to card or row UI must be made in the shared widget; the
adapters only change when a VM's API changes. If a screen needs a new
capability, add a nullable param to the shared widget — never a
per-screen copy.

## How to make a change correctly

1. Ask: *does this belong on all three screens?* (Almost always yes for
   styling/gestures/layout.)
2. Implement in the shared widget; add nullable params for the
   context-specific bits (`onAdd`, `onRemove`, `onReorder`, `readOnly`,
   optional `prefixIcons`).
3. Update all three call sites in the same change — never ship a shared
   widget with one screen still using an old copy.
4. If it's genuinely one-screen-only (e.g. ghost planned targets need
   live session data), implement it in that screen and leave a comment
   noting WHY it's not shared, so the next agent doesn't "fix" it by
   copying or "fix" it by removing.

## Historical incidents (why this skill exists)

- **Variation dropdown was green in the past-session edit row** but
  conditionally colored in the live row — a one-line copy drift. Fixed by
  unifying to primary. Audit the three rows together after any set-row
  change.
- **Planner pills used a green active color** ("planned" semantics) —
  removed in favor of the accent used everywhere.
- **Swipe affordance stripe** — went from accent stripe → hairline → gone
  entirely, and `SwipeActions` being shared meant all screens changed at
  once (the payoff of the shared widget).

## Checklist for review

- [ ] No per-screen copies of a shared component exist
- [ ] Colors/gestures/affordances identical across all three screens
- [ ] Context differences are presence/absence (nullable params), not
      styling
- [ ] New shared widgets live in `shared/widgets/` with param-based modes
- [ ] Any deliberate one-screen-only behavior has a why-comment
