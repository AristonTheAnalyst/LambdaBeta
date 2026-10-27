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
| Past-session viewer | `lib/features/logs/view/session_detail_screen.dart` | The Training view, read-only — same card, caption and floor bar, with view/edit modes (2026-10-22) |
| Planner | `lib/features/programs/view/plan_session_screen.dart` | Editing a template (dim) — the same flat card and floor since 2026-10-26, every stack meaning spent |

## Vocabulary (so we all mean the same thing)

- **Tab bar / pill bar** — the horizontal row of exercise chips under the
  stats bar (tap to switch exercise). Rendered by `ExercisePillBar`.
- **Set row** — one KG/REPS/VARIATION/NOTE grid row inside an exercise card.
- **Ghost target** — the planned-target hint behind a weight/reps cell in
  the live session (shows the planned target while typing).
- **Planned style / planned container** — the user-defined term for any
  container representing something planned: the `lambdaBox(planned)`
  recipe — `plannedBg` fill with a `planned` border at 0.35 alpha
  (unified from 0.3/0.4/0.5 on 2026-08-20). Banners, the selector's closed
  field and a following set row wear it. Exercise cards never take a fill
  (see **flat card** below). Use this recipe for ALL planned containers.
- **The planned grammar** (2026-10-23) — how a planned VALUE reads, live
  rows only (the viewer and planner read; they never chip):
  | Cell | Reading |
  |---|---|
  | empty, a target exists | the target in `planned` ink = **guide only** |
  | real value that meets the plan | `plannedText` (white) on a solid `plannedFill` chip = **real, and is the plan** |
  | real value off the plan | plain cell, `primary` ink = **real, off-plan** |
  Weight chips on equality to a single number only (a range never chips);
  reps chip on equality or inclusive range containment ("9" in "8-12").
  The row keeps the `plannedBg` tint while nothing contradicts a parseable
  target — empty cells don't deviate, non-numeric targets ("AMRAP",
  "3 RIR") constrain nothing, notes never retire it, and a variation must
  be null or the plan's. Any contradiction retires the row to neutral.
  **The variation cell is not a guide cell (2026-10-23):** a variation is
  categorical, not a target — a planned variation is a **real value**, so
  the cell shows the plan's name in `primary` (never the guide blue) and
  the row's first commit adopts it.
- **Flat card** — the session exercise card has no fill and no border of
  its own; the page ground shows through, and its controls (selector,
  pills, set rows, ADD SET) carry their own chrome on the 22pt gutter
  (2026-10-22). No state adds a rim (2026-10-23): a deleted exercise reads
  off its red selector name and red rows, a planned one off the selector
  field and the rows. Every state is otherwise completely flat. See
  [frontend-design] for the geometry.

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
5. **The session header speaks in glyphs (2026-10-20).** The wizard's
   verbs are glyphs, not pills: Back → `arrow_back_ios_new`, Continue/
   Summary → `arrow_forward_ios`, the browse's Start → `add` (a **plus**,
   2026-10-23 — starting a new session from the Sessions browse; the
   Training page's *Start workout* keeps `play_arrow`), Cancel → `close`
   in danger (2026-10-23 — a red **X**, not the square `stop` it used to
   be: the square read as pause/stop the timer, the X reads as close this
   session), End/Done → `check` (success).
   Each carries its word as
   `semanticsLabel` (tooltip + screen-reader label); the word never returns
   as a pill in the header. The same holds in the other two surfaces: the
   planner's Save is a success check, the past-session viewer's
   Edit/Done are `edit_outlined`/`check`. Header controls use
   `HeaderIconButton` (bare) — the glyph-or-word rule is frontend-design §5.
   **One word control (2026-10-23):** the browse's **Resume** — with a
   session live, Home's right slot is a compact green `GlassButton`
   reading Resume, word only, no glyph, because it is the browse's primary
   CTA and the word is the whole point (Start would begin a SECOND
   session). It is the only text button a session header may carry.
6. **The set grid reads KG · REPS · VARIATION (2026-10-22).** Weight first,
   reps second — in the header row and in every set row, on every surface
   that shows the pair. It is the order the rest of the app already speaks:
   a PR line, a log line and a goal target all read "100 kg × 5"
   (`goalTargetValue` composes the goal target in this same order). Never
   render reps-first, and never let one surface flip while another doesn't:
   the grid header and its rows are two halves of one fact.
7. **The past-session viewer IS the Training view, read-only (2026-10-22).**
   No tabs, no identity card, no caption bar, no summary restating the
   page. The two surfaces are one page in two modes:
   - the **header names the session** — plan name, or "Freestyle Session"
     — with `edit_outlined` / `check` on the right (`HeaderIconButton`,
     bare). Nothing else lives in the header; the back arrow is the only
     left control.
   - the **same flat card** on the same 22pt gutter, the same scroll
     padding.
   - the **same floor bar**, date bar first (rule 8), then undo/redo with
     the historic trash, the star (session ratings sheet), and the three
     doors (session PRs → `showPrHistorySheet`, goals → the goals sheet
     with its open count, exercise notes → the grouped `showLessonsModal`;
     all scoped to the record on the bar).
   View mode draws **no write controls at all** (2026-10-26): `+ ADD SET`
   is not drawn, the kg/reps cells are flat text (no fill, no outline) and
   the variation is plain text without its chevron — a record carries no
   affordance that only edit mode can answer. Edit mode brings the whole
   form back. Undo/redo and the trash are **drawn in both modes** so the
   floor never changes shape; only their enabled state moves. If you find
   yourself adding a second presentation of data the card already draws,
   the answer is a door on the floor bar, not a tab.
8. **One floor bar recipe across the session surfaces (2026-10-22).** The
   bar is two rows inside one floor container (`bg` + 0.5 top border,
   padding 16 horizontal / 8 vertical):
   - **Row 1 — `SessionDateBar`** (`shared/widgets/session_date_bar.dart`):
     a ghost box (radius md, 5 inset) reading `TODAY - 22 Oct 2026` in
     accent while the session is the one being logged, or
     `PREVIOUSLY - 20 Oct 2026` in `inkSecondary` while a record is on
     screen. Mono caption, w700, tracking 0.8 on the state; the date is
     primary ink. **Tapping the phrase cycles how the date reads**
     (2026-10-23) — the written date, `N days ago`, `N weeks N days ago`,
     then round; a relative reading drops the `PREVIOUSLY -` phrase and a
     session under a week cycles only date ↔ days. The old reading is cut
     away and the new one scales in; a live session's phrase is inert.
     **The arrows walk one of two stacks, and a radio pair inside the bar
     names the live one (2026-10-23).** Both modes are always visible,
     side by side on a row under the date, inside the same ghost box (it
     grows to hold both rows; the chevrons keep their full width and 40
     height), one checked: `SESSION`
     left, `SESSION BY EXERCISE` right — the labels say what the arrows
     walk (whole records, or the active exercise's own performances), a 14px
     `radio_button_checked` /
     `radio_button_unchecked` glyph (accent / muted) and the date's own
     mono caption (12, tracking 0.6) — primary ink when checked,
     `inkSecondary` when not. Each option claims a 40pt target; only the
     unchecked one is a switch, so tapping the live side does nothing.
     Semantics: mutually exclusive group, checked state, "Session" /
     "Session by exercise"; a null toggle hides the pair, so a bar with one stack
     draws none. **EXERCISE is the default
     on both surfaces**, for consistency:
     - **EXERCISE** walks the active exercise's own past performances: the
       card's sets swap for the stepped-to performance's and the record
       stays the page (header, floor, tiles, sheets). The stack is that
       exercise's performances **strictly older** than the page — home
       (index 0) is the page's own sets, older performances at N, both
       ends holding, nothing newer to walk. A selection is bound to the
       exercise it was stepped on: another exercise arriving on the card
       (picker, undo, a structural edit) reads as home, so no structural
       site has to reset the walk. Arrows read `Previous/Next
       performance`.
     - **SESSION** walks whole records by the rule below; its arrows read
       `Previous/Next session`. Switching modes returns the card home
       (index 0) in both directions, and a SESSION walk carries the
       reader's mode across the step.
     **The phrase is flanked by two `SessionChevronButton`s**
     (40 target, 24 glyph, radius 6, the selector's own recipe) that walk
     the live stack (2026-10-22): older left, newer right. **Every SESSION
     step is in place.** The live Training page's left steps onto the newest
     completed record and hosts it right there (`SessionHistoryPeek`: the
     viewer's own `SessionDetailView` over a `SessionDetailViewModel` from
     `SessionViewModel.createRecordPeek`) — same route and wizard, the
     record's sets and floor drawn under them, and the header's title alone
     following the record (2026-10-23): `SessionDetailState.sessionTitle` —
     the record's plan-name snapshot, `Freestyle Session` when it had none
     — republished through the screen's `_peekTitle` notifier and back to
     the live name on today, while every header control stays put — and the
     newest
     record's right steps back onto today's live sets; the live page never
     pushes /logs. On the /logs route the same page and view model swap
     the record's sets under it (the PR Lab's pager), edit mode and its
     drafts left behind and the walk re-briefed for the record now on
     screen; only its newest record's right arrow onto today is a real
     move — a pop when the route was pushed from live
     (`AppRouter.fromLiveExtra`, the recap card), otherwise the session
     tab. A step the stage cannot take greys
     its arrow; ends are never removed. `isToday` is the **caller's fact,
     not the clock's** — a
     session resumed the next morning still says TODAY, and a session
     recorded this morning is still PREVIOUSLY.
   - **Row 2 — `[UndoRedoButtons | 8 | BarIconButton star | 8 |
     Expanded(SessionStatsTiles)]`**. Every control in the row is a
     `kSessionBarControlSize` **48** square (`BarIconButton`, 24px glyph,
     radius md; the doors stand at the same 48) — the PR Lab's bar recipe,
     so the floor reads at the floating nav bar's scale (2026-10-22). The
     trash rides in `UndoRedoButtons`'
     third slot on both surfaces (live: the session's own deletions;
     viewer: the historic ones) — never in the header. The star wears
     **primary glass on both floors** (2026-10-27; accent until then,
     and never again): it opens the session's feelings, not a score.
     The row's three doors are **trophy · bullseye · note**, each a third
     of the inner slot. **A door is neutral until it has something to
     say** (2026-10-27): `primary` glass and ink while its feed is empty,
     the **accent** glass and ink once it is not — the trophy when the
     session gained PRs (the whole PR shelf on the planner), the bullseye
     when the exercise has open goals, the note when this session carries
     exercise notes. **No door draws a count** (2026-10-27) — all three are
     glyphs alone, the feeds' sizes riding only the semantics. **Every door is a door at any count** (2026-10-23)
     — the sheets hold the exercise's whole story, so a `0` still opens;
     the quiet solid-surface tile is only the no-exercise fallback. The
     trophy opens `showPrHistorySheet` with the card's exercise feed, the
     session on screen's set ids, its start and whether it is live — read
     newest first (2026-10-23): `AFTER` on top, drawn only
     when non-empty, then the session's own shelf split on the ids, never
     the date, headed `THIS SESSION` only when live or by the record's
     date (`20 OCT 2026`) on a past record, then `PREVIOUSLY`; the note
     glyph opens the exercise-notes modal with the same `sessionId` /
     `sessionStartedAt` / `sessionIsLive` and the same three shelves (no
     NEW badge).
     A record a completed review covers also carries that review's
     checkpoint (2026-10-26): the after-group splits once more, `SINCE LAST
     REVIEW` (what landed after the last pass closed) above `AFTER` (what
     landed after the session but no later than it). Both sheets take the
     boundary as an optional `sinceLastReviewAt`; without one the three
     shelves stand exactly as before — the live page never supplies one.
     A date-bar walk moves the sets, the counts and both sheets together.
     **The goals bullseye (2026-10-26; a numbered door since 2026-10-27).**
     Between the trophy and the note stands a `track_changes` control that
     `SessionStatsTiles` draws only when the surface passes `onGoalTap` —
     the live Training floor, the past-session viewer and the planner /
     review workout editor do (2026-10-27); a friend's or athlete's record
     does not (the write would file under their id). It is lit by the
     exercise's **open goals** (`openGoalsFor`, the same `goalCompletionSet`
     reading the sheet uses) and wears the accent glass while that count is
     above 0. It opens `showExerciseGoalsSheet`
     (`features/goals/view/exercise_goals_sheet.dart`) on the PR sheet's
     furniture: the card's exercise named in the eyebrow, its goals,
     **Open** by default behind a status control (Achieved / All), ordered
     by the app's `SortButton` (target date · weight · reps · newest), met
     ones read through `goalCompletionSet` over the same merged timeline
     the `G` badges come from. A PR whose set achieved a goal draws
     **success** instead of accent in the trophy's sheet (the same
     `goalSetIds`).
   **The planner stands on the same floor (2026-10-26).** It has no
   session, so every meaning a session gives the floor is spent rather
   than omitted: `SessionDateBar.plan()` draws the bar's furniture — a
   lone `PLAN` phrase in `inkSecondary` (no state, no date, the phrase
   inert), both chevrons greyed, no radios; the undo/redo pair stands
   with its trash slot **spent outside a pass** (archived groups are
   hidden there, and undo is the way back) and **live inside one**
   (2026-10-28): the card keeps a group the pass removed red, so the
   trash lists the pass's own removals, a row opens one for reading, and
   a **Restore** button under the card un-archives it and every set under
   it — the live session's view-then-restore flow, over the pass's staged
   store; the star stands greyed (a plan has no session ratings); and `SessionStatsTiles(gain: false)` draws the active
   exercise's whole PR feed, goals and notes shelf — the counts behind
   the doors are the whole shelves, and the doors are still doors
   (2026-10-27): the trophy opens `showPrHistorySheet`, the bullseye
   `showExerciseGoalsSheet` (the editor's own `goalTimeline` + `goals`
   read, written through `createGoalFromTarget`) and the note
   `showLessonsModal`. Inside a review pass the floor does not stand
   down for the review bar — it stands under it, and both sheets take
   the pass's checkpoint: with no session on the desk there is no
   after-group to split, so the checkpoint divides the whole shelf
   (`SINCE LAST REVIEW` above `PREVIOUSLY`, no `AFTER`, no session
   shelf). The custom SETS · EXERCISES pill and the review-mode undo
   storey are gone with the custom floor.
9. **A planned exercise is told apart by its values, not its card
   (2026-10-23).** The card draws no rim for a plan. The blue lives where
   the plan lives: `ExerciseSelector.planned` paints the closed field with
   the planned container, a plan-linked row keeps the `plannedBg` tint
   while it follows the plan, and the values speak the **planned grammar**
   (above): target = blue guide, matching real value = white-on-blue chip,
   off-plan value = plain, and a planned variation is a real value in
   `primary`, never a guide. Only live rows chip — the planner's fields ARE
   the targets and the viewer reads history, so neither ever draws one.
   Deleted outranks planned on every one of these surfaces — and a deleted
   exercise's card draws no rim either: its deletion reads off the red
   selector name and rows, and an empty cell still ghosts the plan's target
   (blue guide), so deleting an exercise never erases what it was meant to
   do (2026-10-23). The deleted view's selector lists **every** deleted
   exercise with the viewed one open; picking another flips the card in
   place. A planned
   single-number weight is recorded as the row's real weight at Start and
   therefore chips immediately; **reps are never adopted** — a planned rep
   count is a guide until typed. `lib/core/utils/planned_target.dart` is
   the one parser: everything else (adoption, chips, the tint) reads it.
10. **Browsing never ends a session (2026-10-23).** A re-tap of the Session
    nav tab while the wizard is on screen is a request for the browse: the
    wizard flushes typed values (the same flush every wizard step takes)
    and slides to Home — the embedded **Sessions** browse (the logs list,
    headerless, titled `Sessions`; its Sets tab retired and its filter bar
    the two-row `LogsFilterBar` with the workout filter, 2026-10-23) — with
    the live session still running underneath, and
    `AppRouter.sessionTabReselected`
    is the signal that carries the tap (`go('/session')` is a no-op there,
    so the shell has to say it another way). Only a live session on
    Training or Summary may step away (`browseOnSessionTabRetap`,
    `session_screen.dart`): Home is already the browse, the
    pre-questionnaire has nothing live, and the post-questionnaire is a
    one-way door. The Home header's right slot then reads **Resume**
    (rule 5's one word control) and returns to Training. Nothing on any
    surface ends a session by navigation — only Finish (Summary's check)
    or Cancel (Training's X) does.

## Current shared inventory (already unified)

| Component | Where | Notes |
|---|---|---|
| `ExerciseSelector` | `shared/widgets/exercise_selector.dart` | The pill bar + popover, embedded in the shared card — the only exercise-tab UI since 2026-08-23 (`ExercisePillBar` deleted). |
| `ExerciseTabChip` | `shared/widgets/exercise_tab_chip.dart` | The pill itself. Active color is accent everywhere — do NOT pass per-screen `activeColor` again (the planner's green was removed on purpose). |
| `SwipeActions` | `shared/widgets/swipe_actions.dart` | The session rows' drawers (Goal/Duplicate/Note/Delete — the live grid and the record viewer; the live card's edit-gated history rows keep Note alone). Since 2026-10-23 (promoted from the PR Lab) each action is a trailing **circle** that scales in as its slot is uncovered — trailing action first, no fade anywhere — one drawer is open app-wide, and any tap off the action circles puts the row back. No visual affordance at rest — the swipe gesture is the discovery mechanism. |
| `StatsRow` / `StatsTile` | `shared/widgets/stats_row.dart` | The boxed stat row on the review snapshot. **Not** the session floor: the live session, the viewer and the planner draw `SessionStatsTiles` (`features/session/view/session_stats_bar.dart`) — the three glyph doors (trophy · bullseye · note), `primary` glass while the feed behind a door is empty and `accent` glass once it is not, a door at any count (quiet only when no exercise is on the card); no door draws a count — all three are glyphs alone, the numbers riding only the semantics (2026-10-27); the bullseye stands where the surface passes `onGoalTap` (live, viewer, the planner/review editor and a completed review's record, 2026-10-27); the planner and the record pass `gain: false`, so their counts are the whole shelves (2026-10-26; the record 2026-10-27). |
| `lessons_modal.dart`, `notes_modal.dart`, `pr_history_sheet.dart` | `features/session/view/` | Shared modals. The lessons modal is polymorphic (takes a Listenable + callbacks) and stands the PR Lab's three shelves newest first — `After` (only when non-empty), the session's own shelf (headed by its date unless the caller is the live page), `Previously` — no NEW badge; `pr_history_sheet.dart` (`showPrHistorySheet`) is the trophy's sheet — presentational, fed an exercise's `PrEvent` feed, the selected session's set ids and (optionally) its start, live flag and review checkpoint (`sinceLastReviewAt`, 2026-10-26, which splits the after-group into `SINCE LAST REVIEW` + `AFTER`); `sheet_section_label.dart` is the shared group heading. |
| `DropdownSelect` | `shared/widgets/dropdown_select.dart` | Variation picker; `valueColor` default primary everywhere. |
| `SessionSetRow` | `shared/widgets/session_set_row.dart` | THE one set row (unified 2026-08-22). `SetRowMode { live, planned, history }` derives per-context behavior (formatter, ghost/highlight tint, draft materialization, duplicate guard); orthogonal state is flags (`isPr`, `readOnly`, `plannedTarget`, edit-gate `editConfirmed`/`onEditConfirm`). All VM work goes through bridge callbacks (`onCommit`, `onVariationChanged`, `onNotesSave`, `onDelete`, `onDuplicate`, variation trio). Since 2026-10-13 `onCommit` carries an `immediate` flag — keystroke commits are false (debounce-eligible, merged by the VM into one write per settle), blur and the registered flush handle are true (write now, the no-data-loss safety net); the planner ignores the flag. `deleted` (2026-10-14) is the past-session viewer's soft-deleted row — danger fill/edge/text, forced read-only in either mode. A read-only row (`readOnly`, an unconfirmed gate, or `deleted`) draws **flat cells** — no fill, no outline, and its variation as plain text without the picker's chevron (2026-10-26): a record carries no affordance only edit mode can answer. The swipe drawer carries Note / duplicate / delete; a goal is opened from the floor's bullseye, never from a row (2026-10-26). The planned grammar (2026-10-23) lives here: `planValue` turns kg/reps into the white-on-blue chip (`plannedFill` / `plannedText`), the kg/reps ghost is the blue guide (a planned variation is a real value in `primary` — 2026-10-23), and `_isPlannedRow` holds the tint only while the typed values meet the target. A keystroke repaints before it commits (`_onCellChanged`), and a revert to the seed supersedes the pending write (`_hasPendingCommit`). The row container carries `session-set-row-<mode>-<set|draft>-<n>` so tests read its chrome. The file also owns `recordSetRow`, the one **read-only** row builder — a record is read by two readers (the Compare flip, the record's workout screen) and they must not drift. |
| `SessionExerciseCard` | `shared/widgets/session_exercise_card.dart` | THE one exercise card (unified 2026-08-22). Selector, pinned exercise note (the bar reads it whole in `showPinnedNotePopup` — `View all exercise notes` is its door on to the sheet, 2026-10-23), Notes/History/PRs pills, sets grid, history picker/detail. `flat: true` (2026-10-22) is the session look — no fill, no inner boxes, a 6pt inner inset so every control lands on the 22pt gutter, and **no state rim at all** (2026-10-23): a deleted exercise reads off the red selector and rows, a planned one off the selector field and the rows; the live session, the viewer, the planner (2026-10-26) and a completed review's record (2026-10-27) pass it; only the pass's own workout editor keeps the box. Screens adapt VM state into plain inputs; **null callbacks grey the control** (null `onLessonsTap` → greyed pill, null `onAdd` → greyed Add Exercise, null `onRemoveRequest` → the modal's tick goes informational, null `onAddSet` → no ADD SET, null `history` → History pill greyed). The history detail is the same sets grid (headers + `SessionSetRow`s in `history` mode): the live screen passes edit-gated rows (tap any field → one-time "edit past data" confirm; never swipe actions), the logs screen passes `readOnly: true` rows. |
| `CardPillButton` | `shared/widgets/card_pill_button.dart` | The pill chrome inside the card. |
| `ExerciseSelector` | `shared/widgets/exercise_selector.dart` | Field + anchored popover; `onMove`/`onAdd` are nullable (null greys reorder arrows, greys Add row). Owns `ExerciseMark` — the green **plus** / red **minus** (a filled disc, `Icons.add_circle`/`remove_circle`: a bare stroke at 14px read as a hyphen or a smudge — 2026-10-12) an exercise name wears when its side differs from the other reading (`marks`, parallel to `exercises`; null — or a list that stops short — leaves that name bare): a review's frozen sides, the live session's plan-diff (an exercise added beyond the plan wears the plus, 2026-10-13). The mark rides beside the name in the field and in every popover row, so the name ellipsizes left of it. `deleted` (parallel `List<bool>`, 2026-10-14) gives the name the **deleted box** — the deleted set row's exact chrome, one shared recipe (`deletedBox`), the text left its own colour — the deleted-exercise reading in both the live view and the past-session viewer. `planned` (2026-10-23) paints the closed field with the planned container — the card draws no rim, so the selector carries the plan's provenance; deleted outranks it. The accent restore dot is gone (2026-10-23): the live deleted view's selector lists every deleted exercise by name, so the slot marker has nothing left to say. |
| `AddExerciseModal` | `shared/widgets/add_exercise_modal.dart` | THE add-exercise picker (`showAddExerciseModal`), one copy for all three screens since 2026-09-29 — replacing the three copy-pasted `_AddExerciseContent`s and the hold-to-delete X. Stay-open multi-select: tap to add, tap a ticked row to remove (the screen owns the confirm dialog), `+ Create` adds without popping. |
| `SessionBookend` | `shared/widgets/session_bookend.dart` | One pre/post questionnaire section — the prep/post pages and the ratings sheet (`showSessionRatingsSheet`, live + viewer, 2026-10-22). Null callbacks keep it read-only; non-null make stars/notes editable. |
| `showSessionRatingsSheet` | `features/session/view/ratings_sheet.dart` | The star's sheet on both session bars: pre + post feeling and notes, the same two `SessionBookend`s the wizard pages draw. Null callbacks = reading a past session; non-null = editing its drafts. A surface with a read/edit **mode** passes `onEditingChanged` and the sheet grows its own pencil, in the close button's container just left of the X (2026-10-27; `Icons.edit_outlined`, accent glass while editing / primary glass while reading), which drives the caller's `startEditing`/`cancelEditing` and gates the draft callbacks in place — the live session (one mode) and read-only records (no mode) draw no pencil. Keys `session-ratings-sheet` / `-edit` / `-close` / `-pre` / `-post`. |
| `LambdaInput` / `LambdaReadout` / `LambdaSearchField` | `shared/widgets/` | The text-box rule (2026-10-07): EVERY editable box is `LambdaInput` (dense search boxes: `LambdaSearchField`), EVERY read-only box is `LambdaReadout` — the field it stands in for with the fill taken out (C · Hollow, 2026-10-28), so a read/edit pair moves only its fill and the mode reads the same on every surface. The note modals, the bookend and the exercise card's review note all wear them, so text looks the same wherever it is read. An editable box's fill is one tier above its ground — `surface` on the page, `surfaceHigh` on a card or default sheet (`elevated: true`; 2026-10-08) — with one named exception: the exercise card's review note box copies the session-prep reference field exactly (base fill, no step up; 2026-10-08). Full rule: frontend-design §6. |

## Per-screen adapters (thin shells — do not add card/row chrome here)

The three screens own only their shells (headers, wizard, stats-bar
placement, footers) and a private adapter that maps their VM into
`SessionExerciseCard`/`SessionSetRow`:

- `lib/features/session/view/live_exercise_card.dart` — `LiveExerciseCard` (SessionViewModel).
- `lib/features/session/view/session_history_peek.dart` — `SessionHistoryPeek`, the live Training page's record host (2026-10-22). It is not a fourth editor and owns no chrome: it draws the viewer's `SessionDetailView` verbatim over a `SessionDetailViewModel` (`createRecordPeek`), wiring the date bar's steps in place and the newest record's right arrow back onto today.
- `lib/features/programs/view/plan_session_screen.dart` — `_PlanExerciseCard` (ProgramDetailViewModel; pills greyed by decision).
- `lib/features/logs/view/session_detail_screen.dart` — `_DetailCardBuilder` (SessionDetailViewModel; edit-mode flags gate the callbacks).
- `lib/features/programs/view/record_workout_screen.dart` — a **reading**, not a fourth editor (2026-10-12; a stack since 2026-10-26; the pass editor's own floor since 2026-10-27): every frozen version of one workout — the current plan, then each completed review's end (`snapshot_content`, as it completed) and start (`baseline_content`, as the pass found it), newest first — wearing the pass's own chrome, `ReviewBar` included, via `reviewChrome(context, session:, readOnly: true, loadComparison:)`, over the **same floor as the pass editor** (`KeyboardFloorLayout`; `record-workout-bar`): a version walker in the session date bar's ghost-box furniture (`Container` + `SessionChevronButton`s + a mono caption, not a `FloatingBar`) steps the stack older left / newer right and names the version on screen (`START OF REVIEW - …` / `END OF REVIEW - …` / `CURRENT PLAN`); below it the planner's actions row — undo, redo and the trash spent, the star disabled — beside live `SessionStatsTiles(gain: false)` doors, which read the active exercise's whole PR feed, its open goals and its notes shelf and open the read-only sheets (the pass's `sinceDate` as the checkpoint, no New goal, `readOnly` notes). `RecordWorkoutViewModel` (`ValueNotifier<RecordWorkoutState>`) owns the walk, the sibling pair, the marks' reference and those shelves (`loadContext`, read once after the page opens, each read's failure leaving its door quiet); every version is read before the page opens, so a step repaints rather than loading. It adapts plain `ContentExercise`/`ContentSet` rows and is the shape every other read-only surface should copy: `onMove`/`onAdd`/`onAddSet` null (the controls grey or are not drawn), rows via `recordSetRow` (see above), `reviewNote` with a null `onReviewNoteChanged` (notes ride the versions the review produced — an end — and read "No note" on a start), and `flat: true` on the card — the doors live on the floor, so the pills row is not drawn. It is also the only surface that pairs a mark with a minus, and the pair's marks both live on the **end** (2026-10-27): an exercise the end holds and its start does not wears `ExerciseMark.added` (green plus), and a group the start held and the end does not — which the snapshot dropped, so the end has no row of its own — is drawn as a card from the start's frozen copy wearing only `ExerciseMark.removed` — the ordinary selector name and its plain sets, its pass note where one was left, at its old plan position after any kept group sharing the slot. The red minus is the whole reading: on a record a removal is the mark, never a repaint (unlike the open pass, which still draws a group removed during it red, 2026-10-27). The start is the baseline and wears no marks at all — a live pass, whose tabs are always the plan's, shows the plus alone. The current plan's reference is the newest end, so its marks say what has changed since the last record. Switching exercises stays — looking is not writing — and the eye jumps between the two sides of the review on screen (offered only where both hold the workout; never on the plan). On a record the bar's verbs wear what the record says rather than writing it: the tick is drawn green and disabled, the note glyph greyed, and the label names the frozen side on screen (`kReviewAfterLabel` / `kReviewBeforeLabel`, green turning accent as the eye turns; `ReviewBar.recordLabel` reads `Current Plan` over the plan itself) rather than the walk a pass's label reports.

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
