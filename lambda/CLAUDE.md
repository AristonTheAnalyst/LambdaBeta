# Lambda — Workout Tracking App Architecture

## Project Structure

```
lib/
├── core/                    # Design tokens, utilities
│   └── styles/              # AppColors, AppFonts, AppRadius, AppSpacing, AppTextStyles
├── data/
│   ├── models/              # Plain Dart data classes with fromMap/toMap
│   └── repositories/        # PowerSync/SQLite data access layer
├── features/
│   ├── session/             # Active training session (primary UX foundation)
│   ├── programs/            # Program + planned session editor
│   ├── logs/                # Training Logs + past-session viewer
│   ├── exercises/           # Exercise library & configuration
│   ├── auth/                # Authentication screens
│   ├── profile/             # User profile
│   ├── statistics/          # Analytics/statistics
│   ├── dev/                 # Developer screens
│   └── onboarding/
├── shared/
│   ├── router/              # go_router configuration
│   └── widgets/             # Shared UI components
└── main.dart
```

Naming rules (2026-08-13 redesign, 2026-08-26 amendment): `dim_*` = reference data. Top-level dims (exercises, variations, planned sessions, programs) soft-delete via `date_archived` timestamptz (NULL = active — sortable, latest archived first); their child tables and `dim_lesson` keep the boolean `is_archived` (internal lifecycle only). `fact_*` = events. "Workout" language is banned in the DB — templates are **planned sessions**, logged workouts are **sessions**. See the `app-features` skill for the complete table inventory, RLS matrix, and sync wiring; the `sync-contract` skill for schema/sync changes.

## Core Architecture: The Three Session Screens

The app has three session surfaces that share one UX. **The live session screen is the primary design foundation** — the other two mirror its patterns via shared widgets (see the `session-ux-consistency` skill for the rules).

### 1. Session Screen (`lib/features/session/`) — Active Training

**Purpose:** Log a live workout in real-time. The most feature-rich screen.

**Structure:**
- `view/session_screen.dart` — `SlidePages` wizard, 5 pages (indices are `SessionViewModel.k*Page` constants): 0 = Home (congrats banner + last-session recap, Start), 1 = Pre-Questionnaire (feeling/notes + last-session recap, Continue), 2 = Training (active workout; idle state shows `_SessionTemplateCard` template picker + `_SessionPreview` read-only preview), 3 = Summary (THIS SESSION recap, Finish Session), 4 = Post-Questionnaire (feeling/notes + completed-session recap, Done → Home). Pre answers are written at session creation (Training's Start); post answers via `updatePostQuestionnaire` on Done, after `endSession` stamps only `end_datetime`.
- `viewmodel/session_viewmodel.dart` — `SessionViewModel`, a `ChangeNotifier` with mutable fields (NOT an immutable state class).
- `view/live_exercise_card.dart` — `LiveExerciseCard`, a thin adapter over the shared `SessionExerciseCard`/`SessionSetRow`.
- Renders: `SessionExerciseCard` (with `ExerciseSelector` pills, pinned lesson, Lessons/History/PRs pills) → `SessionSetRow` grid + rest timer + stats bar.

**Key features (priority order):**
- Exercise selector (pill popover: switch, arrows reorder, add — removal is un-ticking a row in the add-exercise modal)
- Exercise card: planned outline, PR count badge, pinned lesson bar, history picker
- Inline editable set grid: REPS/KG/VARIATION/NOTE columns, `SessionSetRow` (mode `live`):
  - `FilteringTextInputFormatter` numeric-only weight/reps
  - Auto-commit on blur (weight/reps)
  - Ghost planned-target hints (planned text from the linked dim row)
  - PR accent row (background + border turn accent)
  - Swipe-to-duplicate, swipe-to-delete
  - Variation dropdown with "Did you mean?" dedup + inline create-new
  - Notes icon modal
- Stats bar: SETS / PRS (tappable → PR modal) / EXERCISES / AVG REST
- Rest timer bar + hold-to-finish End Workout
- Home page: congrats banner (with the finished session's stats), last-session recap card, Start
- Pre-questionnaire page (after Start): feeling picker (1-5), pre-notes, last-session recap card — nothing persisted until the workout starts
- Post-questionnaire page (after Finish Session): feeling picker, post-notes, completed-session recap card — Done writes the answers and lands Home

### 2. Planner Screen (`lib/features/programs/view/plan_session_screen.dart`) — Planned Session Editor

**Purpose:** Plan a future session (template) inside a Program, or standalone.

**Structure:**
- Pushed via `MaterialPageRoute` from `program_detail_screen.dart`
- Shares the same `ProgramDetailViewModel` (constructor param)
- `ProgramDetailState` — immutable `ValueNotifier` with `copyWith`
- `_PlanExerciseCard` — adapter over the shared `SessionExerciseCard`; rows use `SessionSetRow` mode `planned` (free-text targets)

**Key features:**
- Editable inline header (tap to rename, auto-commit on blur), session notes
- Stats bar: SETS / EXERCISES (no PRs/rest — no live data)
- Exercise selector (arrows reorder → `exercise_sequence_order` persisted)
- Lessons/History/PRs pills greyed by decision
- Add exercise modal (single-exercise only — no superset)
- Save button (appears when dirty) + auto-commit on blur
- Delete session with confirmation dialog

**Deliberately excluded:** PRs, rest timer, feeling picker, ghost targets (the fields themselves ARE the targets).

### 3. Past-Session Viewer (`lib/features/logs/view/session_detail_screen.dart`) — Completed Session

**Purpose:** Review and edit a completed session from Training Logs.

**Structure:**
- Navigated via go_router from `logs_screen.dart` (`/logs/:sessionId`)
- `SessionDetailViewModel` — `ValueNotifier<SessionDetailState>` (immutable)
- Two modes: **view** (read-only) and **edit** (inline editing)
- Exercise tabs order from the persisted `fact_session.exercise_order` (fallback: first-appearance in set rows); edit-mode reorders persist back to it

**Key features:**
- Same shared card/row layout as live/planner (`_DetailCardBuilder` adapter; rows mode `history`)
- 4-tile stats bar: SETS / PRS / EXERCISES / AVG REST
- PR detection via the derived-on-read PR engine
- Planned outline (from `session.parentSessionId`); per-row planned linkage via `parent_set_id`
- Pre-workout feeling display (1-5 indicators)
- Edit mode: same set-row grid with swipe actions, add exercise, "+ ADD SET"
- Pre/Post notes in footer bar (edit mode only)
- Lessons/History per exercise (same shared modals)

**Excluded:** rest timer (no rest data), elapsed timer, superset display.

## Data Models

### Core session models (`lib/data/models/`)

| Model | DB Table | Purpose |
|---|---|---|
| `Session` | `fact_session` | A completed/active session |
| `SessionExercise` | `fact_session_exercise` | One exercise tab within a session (the layer between session and sets) |
| `SessionExerciseSet` | `fact_session_exercise_set` | One logged set within a session exercise |
| `PastSetRow` | extends SessionExerciseSet | Adds `sessionCreatedDate` for history timeline |
| `PlannedSession` | `dim_planned_session` | Template for a planned session (standalone or in a program) |
| `PlannedSessionProgram` | `dim_planned_session_program` | M2M join row — program membership + schedule slots |
| `PlannedSessionExercise` | `dim_planned_session_exercise` | One exercise group within a planned session |
| `PlannedSessionExerciseSet` | `dim_planned_session_exercise_set` | Target row within a planned exercise group |
| `ExerciseDetail` | `dim_exercise` | Thin wrapper (variations are a flat library — no bridge) |
| `CustomVariation` | `dim_variation` | A variation (e.g. "Incline", "Paused") |
| `Lesson` | `dim_lesson` | Per-exercise text cue/prompt |
| `Program` | `dim_program` | A program containing planned sessions (no progression mode; `uses_blocks` = its shape) |
| `ProgramBlock` | `dim_program_block` | An ordered, duration-bounded phase holding workouts and goals |
| `ProgramReview` | `fact_program_review` | A recorded pass over a set of workouts + goals — standalone when `programId` is null; snapshot, baseline, tick map, exercise/workout notes, outcome |
| `ProgramRun` / `ProgramProgress` | `fact_program_run` | Active program tracking (carries `progression_mode` + `block_id`) |

### Key model fields

```
Session: sessionId, userId, createdDatetime, endDatetime (NULL = active),
         preNotes, postNotes, preFeeling, postFeeling, programRunId,
         plannedSessionId (the template link), plannedSessionName (snapshot)

SessionExercise: sessionExerciseId, sessionId, exerciseId (nullable — free tab,
                 FK → dim_exercise), exerciseOrder (real column — replaced the
                 old JSON blob), exerciseName (hydrated live from dim_exercise),
                 plannedExerciseId (ghost-hint anchor)

SessionExerciseSet: sessionExerciseSetId, sessionExerciseId, sessionId,
                    variationId (FK → dim_variation), setNumber, weight,
                    reps (List<num>), notes, variationName (hydrated live),
                    plannedSetId (plain ref to the template row)

PlannedSessionExercise: plannedExerciseId, plannedSessionId, exerciseId,
                        exerciseOrder, exerciseName (hydrated live), isArchived

PlannedSessionExerciseSet: plannedSetId, plannedExerciseId, variationId,
                   setNumber, targetWeight (free TEXT — "60" or "60-70"),
                   targetReps (free TEXT — "10", "8-15", "AMRAP", "3 RIR"),
                   targetNotes, variationName (hydrated live)

PlannedSessionProgram: plannedSessionProgramId, programId, plannedSessionId,
                       sequenceOrder (order split), dayOfWeek + weekOffset
                       (frequency split — fortnight)

PlannedSession: sessionId, name, notes, createdDate (standalone when no join row)
```

## How Planned Sessions Work

- **Template** = `dim_planned_session` + `dim_planned_session_exercise` + `dim_planned_session_exercise_set`. Targets are **background values**: free text by design ("8-15", "AMRAP", "3 RIR") — a plan is a hint layer, not a contract. There is **no validation** tying what gets logged to what was planned.
- **Program membership** = `dim_planned_session_program` join rows (M2M — one template can sit in several programs). Schedule slots (`sequence_order`, `day_of_week`, `week_offset`) live on the join row; progression mode ('frequency' | 'order') lives on the **run** (`fact_program_run.progression_mode`), chosen at run start.
- **Start** (`SessionViewModel.startWorkout`) → `createSession` writes `fact_session` with `planned_session_id` (FK) and `end_datetime` NULL, then **materializes** the plan two levels deep: one `fact_session_exercise` per planned exercise (with `planned_exercise_id` + `exercise_order`), then one `fact_session_exercise_set` row per planned target with `planned_set_id` = the dim row's id, `set_number` copied, actual values empty. Planned targets render as ghost hints looked up by `planned_set_id` (id-anchored, never positional); actual values (`weight`, `reps`) are strictly numeric.
- **Log** — typing commits to the row's own id. Weight/reps/variation/notes from the plan never prefill actual values.
- **End** (`endSession`) → flush pending edits, delete **untouched planned rows** (planned link + no weight/reps/variation/notes — they were hints, so logs show what actually happened), set `end_datetime = now`. **Empty sets are valid**: any row the user added or touched persists, completely empty ones included.
- **Restart** — restore loads the template via the persisted `planned_session_id` (not the default picker), and re-pairs rows by `planned_exercise_id`/`planned_set_id`.
- Editing the template never affects logged sessions' VALUES (the planned link is a plain ref, no FK). **Names** are different: exercise/variation names live in the dims and update everywhere — renames apply to all past data (the rename flows warn about this). No name snapshots exist (dropped 2026-08-26).

### Workflow: Plan → Log → Review

```
Program → PlannedSession → PlannedSessionSet
             │
             ▼ (startWorkout creates fact_session + materializes planned rows)
Active Session → SessionSet (logged; parent_set_id links to the template row)
             │
             ▼ (endSession: is_active = 0, untouched planned rows pruned)
Completed Session → Training Logs (review/edit)
```

## Programs, Runs & Reviews

- **Program shape** — a program either uses blocks (ordered, duration-bounded phases: `dim_program_block`, length = weeks × 7 + days) or is a simple list of workouts. `dim_program.uses_blocks` is stored, fixed at creation — never inferred. Workouts join via `dim_planned_session_program`; a run follows one block at a time (`fact_program_run.block_id`).
- **A run** (`fact_program_run`) is the commitment to doing the program. Starting a run ends the previous current one; **"End program" ends the RUN**, never the program. Order-based runs **wrap** — the cursor is `completed % sessionCount`, so carrying on past the length needs no new length. Day scheduling (day picker, Frequency progression) is retired from the UI (2026-10-03); data layer kept.
- **A review is standalone** (`fact_program_review`, 2026-10-07): **workouts and goals**, picked directly — `program_id` NULL means exactly that (`isStandalone`). `session_ids_json` is the ordered planned-session ids it covers, `goal_ids_json` the ordered goal ids at any scope, `reviewed_sessions_json` one timestamp per Done (so a pass's ticks persist across app exits), `exercise_notes_json` keyed by `planned_exercise_id` and `workout_notes_json` by `planned_session_id` (both written through as typed — not lessons, not carried forward). Legacy rows carry `block_id`/`session_id` instead — `ProgramReview.sessionsIn(links)` resolves any row to its set (a standalone row reads its own stored set and stops; otherwise stored set → single session → block's sessions → whole program, empty resolutions falling down the chain), and `reviewScopeKey` is the shared canonical key (sorted ids, legacy triple fallback), so a standalone pass over {A,B} and a program pass over {A,B} deliberately chain. `completed_date` NULL = **open** (no status column).
- **Starting one**: the **Reviews tab in the Library is the only start surface for now** (`lib/features/reviews/`) — `+` → name sheet → **selection screen** (tick workouts, tick goals; both lists offer everything the user has, whatever program it hangs off) → Start review. Goal-only passes are refused (≥1 workout). The workout list is ordered **last logged, then newest created** (`fetchReviewableRows`: `MAX(fact_session.created_datetime)` per `planned_session_id` desc nulls last, then `dim_planned_session.created_date` desc, then id desc) — `dim_planned_session` has **no updated_date**, so recency comes from logged sessions or not at all. **Beginning** (`beginReview`) writes the row plus an "as found" baseline from the live rows — idempotent, so a resume never moves it. Scheduling is retired from the UI (repo/VM plumbing kept, like day scheduling). An open pass can be **cancelled**: swipe its IN PROGRESS card (`SwipeActions`, danger) → confirm dialog → `deleteReview` hard-deletes the row, guarded `completed_date IS NULL` so a pass completed elsewhere survives. The ticks, notes, baseline and snapshot are columns on that one row — nothing else goes with it — and cancelling a scheduled pass also removes its `kDueReview` item (the only dismiss path one has).
- **The pass**: the **landing** (`_ReviewLanding`) — **Workouts | Goals** tabs under the header, one card per workout (tick + date once Done) on the first and one per picked goal (tap → read-only view) on the second; a pass with no goals gets no strip, rather than an empty tab. Tapping a workout pushes the real editor (edit mode) with the review bar below: **Note** (workout-level, accent when one exists) **· Compare** (that workout) **· Done** (a toggle: the mark settles the editor → `markWorkoutReviewed`; the same tick again calls `unmarkWorkoutReviewed`, no settle — retracting a claim asks nothing). The workout stays open either way and the bar answers on itself: it reads the tick off `ReviewSession.reviewed`, so `setActiveWorkoutDone` moving the notifier IS the answer ("Review Complete" + green rim, or back to the pass's words; 2026-10-09). **Finish** is on the landing only; with unticked work left it asks "N of M reviewed — finish anyway?" before the notes sheet, then `completeReview` writes a `ProgramContent` snapshot and stamps completion + outcome in one transaction. The snapshot is **the whole program** for a program review and **the set + picked goals** for a standalone one (`buildContentForSessions`); reads narrow it (`contentInScope`, which keeps an explicitly picked goal even when its block holds no reviewed workout). **Compare** diffs the newest COMPLETED predecessor whose set **contains** that workout, both sides narrowed to it, else the baseline — a standalone review walks every review the user has, a program review its own. While the eye is up the plan's own tabs mark the names the record does not hold with a green **plus** (`ExerciseMark`, a filled disc so the stroke does not read as a hyphen against the name); a dropped exercise is never listed, so a live pass shows **no minus** — and the marks go with the flip, so a pass at rest is bare (2026-10-12). A dismissed review completes with no snapshot. The proposal path is deleted (2026-10-06) — `proposed_content`/`proposed_hash` columns stay, dormant. **A completed review opens as a record** (`2026-10-11`): tapping a COMPLETED card pushes `openCompletedReview` → `ReviewRoute(readOnly: true)` under its own route name (`kReviewRouteNameRecord` — a record must never be what `unwindReview` pops down to) — the same landing, read only: cards with no swipe and no add tiles, the ticks as recorded, the bar reading "Review Complete" over a green rim, and a third **Summary** tab ("Nothing here yet." — a placeholder for now, on records only). Nothing is published to `reviewSessionNotifier` and nothing writes — a record is not a pass, and the opener refuses while one is live. **A record reads** (`2026-10-12`): both lists are doors into readings. A workout card opens `RecordWorkoutScreen` — the pass's own chrome (header, shared card, the review's bar at the floor) over the record's **two frozen sides**: the baseline as `beginReview` found it and the snapshot `completeReview` wrote, both narrowed by `contentInScope`, never the live plan (which keeps being edited and would rewrite history under the reader). **The names carry the sides' disagreement** (`2026-10-12`): an exercise the side on screen holds and the other does not wears a green **plus** (added since the base) or a red **minus** (dropped) — `ExerciseMark`, each a plus or minus inside a filled disc, drawn on the shared selector's name in the field and in every popover row, one membership test with two readings so the marks can never disagree across the eye, names both sides hold bare, and no marks at all when the record kept only one side. The **eye flips between them** — `BEFORE · 8 Oct 2026` / `AFTER · 9 Oct 2026` on a page caption AND on the bar's own label, which on a record's workout names the side on screen (`kReviewAfterLabel` / `kReviewBeforeLabel`) rather than the walk: both of a record's documents are frozen, so the bar says which one is being read — green rim and words at rest, turning accent as the eye turns, through the label's usual rise — where a pass reads what the PASS is ("Review Complete" outranking what is on screen, "In Review", "Previously"); a record with only one side offers no eye. The bar is handed the row's `ReviewSession` (`reviewChrome(session:, readOnly: true, loadComparison:)`) rather than publishing one, the tick drawn wearing the record's answer and disabled — green under `GlassButton`'s half opacity when the record says Done — the note glyph greyed, and Compare/Changes reading those same two documents through the injected comparison. Every callback is null or inert (no reorder, no add, no ADD SET, Lessons/PRs greyed, the review's notes reading back — the exercise's box under its sets holding its place either way, `'No note'` where the review left none, the workout's above the card when it has one) with exercises switchable, because looking is not writing. The row is read on the route before the push, so the screen is plain data with no loading state; a row with no snapshot (a dismissed completion, a pre-snapshot row) says so instead of drawing an empty grid. A goal row opens the same `showGoalSheet` with `onDescriptionChanged: null` — the sheet's **record** state: no pencil, no tap-to-edit, no "Add a note…", and no NOTES section when the record left none; the axes still read live history, which a review never froze. The program history panel keeps `showReviewDetailSheet` (the WHAT CHANGED diff the landing never shows).
- **Program/run surfaces are retired from the UI, plumbing kept** (2026-10-07): the program panel's Review button is gone (its history tab resumes passes, never creates them), and a length-reached run answers the prompt directly with **Continue / Change length / End run** (`_answerRunFinished`) instead of opening a review. `fetchDueItems` never returns a standalone row (`program_id IS NOT NULL`), and `kDueRunFinished` still needs `hasCompletedReviewForRun` — which is why **Continue no longer clears the banner**: nothing writes the completed review that satisfied it. Nothing ever ends a run by itself.

## ViewModel Patterns

1. **`ChangeNotifier`** (mutable state, `notifyListeners()`): `SessionViewModel` — the only one; mutable fields with derived getters.
2. **`ValueNotifier<State>`** (immutable state, `copyWith()`):
   - `ProgramDetailViewModel` with `ProgramDetailState`
   - `SessionDetailViewModel` with `SessionDetailState`
   - `LogsViewModel` with `LogsState`

Rule of thumb: complex state needing selective rebuilds → immutable state; tightly coupled logic with many derived properties → ChangeNotifier (session screen).

## Shared Widgets (`lib/shared/widgets/`)

| Widget | Used By | Purpose |
|---|---|---|
| `session_exercise_card.dart` | All three screens | THE exercise card (selector + pinned lesson + pills + sets grid). Null callbacks grey/hide controls. Forwards `exerciseMarks` to the selector — empty everywhere but a review. |
| `session_set_row.dart` | All three screens | THE set row — `SetRowMode { live, planned, history }` + flags (`isPr`, `readOnly`, `plannedTarget`); registers a commit handle for lifecycle flushes. Also owns `recordSetRow`, the one read-only row builder (the Compare flip and the record's workout screen share it). |
| `exercise_selector.dart` | All three screens | Pill popover: switch / arrows reorder / add. Null callbacks grey the arrows and the Add row. Owns `ExerciseMark { added, removed }` — the green plus / red minus (a **filled disc** — a bare stroke read as a hyphen or a smudge at this size; 2026-10-12) a review's name wears (`marks`, parallel to `exercises`; the enum holds the glyph only, the colour resolves at draw time because the tokens are theme getters). |
| `add_exercise_modal.dart` | All three screens | THE add-exercise modal (`showAddExerciseModal`). Stays open: tap to add (green tick), tap a ticked row to remove (caller confirms). |
| `exercise_tab_chip.dart` | `ExerciseSelector` | The pill itself. Active color is accent everywhere. |
| `lambda_input.dart` / `lambda_readout.dart` / `lambda_search_field.dart` | All screens | The text-box trio (2026-10-07): every editable text box is `LambdaInput`, every dense search box is `LambdaSearchField`, every read-only text box is `LambdaReadout`. Never hand-roll an `InputDecoration` or leave text in a bare `Text`. |
| `card_pill_button.dart` | `SessionExerciseCard` | Lessons/History/PRs pill chrome. |
| `swipe_actions.dart` | Set rows, Reviews list | Swipe-to-reveal Duplicate/Delete — and Cancel on an open review card (the drawer reveals, the dialog decides). |
| `stats_row.dart` | All three screens | StatsRow + StatsTile. |
| `page_header.dart` | All screens | Standard app header bar. |
| `floating_bar.dart` | Nav bar, review mode | THE floating bottom container (blur + rounded + shadow + the `Material` ancestor that keeps text off MaterialApp's yellow-underlined error style) + `FloatingBarOverlay` (`contentInset`). Any bar at the floor wears it — nav bar today, review's `ReviewBar` next, and the intended home for persistent notifications on navbar-less screens. |
| `glass_button.dart` | All screens | Accent outline button. |
| `segmented_control.dart` | Program screens, session detail | Segmented option control (tabs, scope/kind pickers). |
| `menu_popover.dart` | Library screens, review scope sheet | THE anchored toolbar menu (2026-10-10): `MenuPopover` hangs a trigger's panel in the overlay — a tap outside closes the menu alone, never the sheet under it — and owns `ChoiceRow`, the tick row both menus draw. |
| `sort_button.dart` / `filter_button.dart` | Library screens, review scope sheet | The toolbar's ordering/narrowing pair, both hung off `MenuPopover`: `SortButton` picks a criterion in its natural direction and closes, and re-tapping the criterion in force flips it (the active row's ↓/↑ arrow is the reading); `FilterButton` closes on pick and goes accent while active. `elevated` steps the panel up on a `surface` ground. |
| `dropdown_select.dart` | All set rows | Variation picker with search + create-new. |
| `slide_up_modal.dart` | Add exercise, notes, pickers | Bottom sheet modal (`showLambdaModal`). |
| `reflection_summary.dart` | Session prep/reflection | Shared before/after recap widget. |

## Shared Modals (from `lib/features/session/view/`)

| Modal | Imported By | Pattern |
|---|---|---|
| `lessons_modal.dart` | All exercise cards | Takes `Listenable` + callbacks (not a concrete VM) |
| `notes_modal.dart` | All set rows | Simple stateless function |

## Repository Layer (`lib/data/repositories/`)

Each repository wraps PowerSync SQLite CRUD.

- `SessionRepository`: createSession, endSession, updateSessionNotes, reorderSessionExercises, cancelSession, getActiveSessionId, insertSessionExercise, updateSessionExercise, loadSessionExercises, deleteSessionExercise, insertSet, updateSet, deleteSet, loadSetsForSession, reorderSets, loadSessionsWithSets, loadPastSetsTimeline, fetchSession, findLastSetForExercise(Variation)
- `PlannedSessionRepository`: fetchPlannedSessions (standalone or via program links), fetchPlannedSessionById, fetchPlannedExercises, fetchPlannedSets, createPlannedSession, updatePlannedSession, deletePlannedSession (archives + its groups/sets, hard-deletes links), createPlannedExercise, deletePlannedExercise, createPlannedSet, updatePlannedSet, deletePlannedSet, fetchNormalizedPlannedSets, duplicatePlannedSession, swapExerciseOrders, renumberExerciseOrders, fetchProgramLinks, fetchLinksForSessions (batch), createProgramLink, updateProgramLink, deleteProgramLink, fetchReviewableRows (every active workout + its last-logged date, in recency order — the review picker's read)
- `ProgramRepository`: fetchPrograms, fetchArchivedPrograms, fetchProgram, createProgram, updateProgram, deleteProgram (archives), hardDeleteProgram (dependent-row order — sessions stay, unlinked), reactivateProgram, programSessionCount, touchProgram, fetchPlannedSessions(programId), duplicatePlannedSession, importWorkoutIntoProgram, pushWorkoutToLibrary, fetchProgramWithSessions, duplicateProgram, fetchBlocks, fetchBlock, createProgramBlock, updateBlock, reorderBlocks, archiveBlock, reactivateBlock, fetchArchivedBlocks, duplicateBlock, fetchBlocksByIds (batch), fetchGoals, fetchGoalOptions / fetchGoalOptionsByIds (goal + its program/block names — the scope chips), createGoal, deleteGoal, rememberDefaultTargetSessions, fetchActiveBlockCounts
- `ProgramRunRepository`: getCurrentRun, startProgramRun, updateRunConfig, endCurrentRun, endRun, fetchProgramHistory, fetchPausedRuns, fetchPausedRun, fetchRunById, fetchRunsForProgram, pauseCurrentRun, resumeRun, getNextPlannedSession (order-based — the run config owns the session count), getProgress, progressFor
- `ProgramHistoryRepository`: scheduleReview, beginReview (row + "as found" baseline, one move), fetchReview, fetchReviews (one program), fetchReviewsForUser (every review, any scope — the Reviews tab's read), fetchOpenReviewForRun (newest open pass for the run), hasCompletedReviewForRun, captureBaseline (idempotent), markWorkoutReviewed (read-modify-write tick map, guarded on open), comparisonBase(review, sessionId:) (newest completed pass whose set contains that workout, else baseline; the pool follows the review's own scope), setExerciseNote, setWorkoutNote (same contract, keyed by `planned_session_id`), completeReview (snapshot = the whole program, or the set + picked goals when standalone), closeRun, deleteReview (hard-delete an open pass — guarded `completed_date IS NULL`), fetchDueItems (never a standalone row), checkpointFor (latest completed pass whose set intersects; the program's own needs a full pass), checkpointForSet (the standalone twin), fetchScopedSessions, weightWindow, buildContent, buildContentForSessions
- `ExerciseRepository`: fetchExerciseDetailMap, fetchVariations, findExerciseByName, createExercise, reactivateExercise, findVariationByName, createVariation, reactivateVariation, deactivate/update variants
- `LessonRepository`: fetchLessons, createLesson, updateLesson, setPinned, deleteLesson

## PR Methodology

PRs are **fully derived on read** — there is no PR table. On every relevant read, the engine (`lib/features/session/model/pr_engine.dart`, used via `pr_service.dart` / `_recomputePRs`) walks logged `fact_session_exercise_set` history chronologically (2026-08-29 frontier redesign):

- **The definition**: a set (w, r) is a PR iff it extends its pair's best-ever frontier — no prior set did ≥ r reps at ≥ w weight (Pareto dominance). 100 × 5 after 110 × 1 IS a PR; 100 × 4 after 100 × 5 is not; an identical repeat is not. One set = **one `PrEvent`**, even when it beats prior records on both dimensions at once.
- **Scope**: per (exercise × variation) — null variation is its own key. Bodyweight is weight 0.
- **Before-facts**: each event carries the two previous frontier values it beat — `beforeWeight` (previous best weight at ≥ this many reps) and `beforeReps` (previous best reps at exactly this weight). A 100 × 10 after 6 × 10 and 100 × 3 renders "was 6 × 10 · 100 × 3". Both null = "First PR".
- **Counts, accents, badges, and modals** all use events (one number everywhere — the live stats bar and the logs summary can never disagree).
- **Lenses (insights only)**: rep-max curves, weight-max curves, and per-axis progressions (`repMaxCurve` / `weightMaxCurve` / `repAxisHistory` / `weightAxisHistory`) are pure projections over raw history — they never gate detection. `kTrackedRepCounts` is a display config for the insights curves, nothing more.
- **Edit-past-data self-heals**: correcting a set changes every PR view on the next read; no stale rows to clean up.

Full spec: `docs/pr_methodology.md`.

## Design Tokens

- Colors: `AppColors` (bg, surface, surfaceHigh, primary, accent, accentBg, accentText, muted, border, success, successBg, danger, dangerBg, history, historyBg, planned, plannedBg)
- Fonts: `AppFonts.ui` (Manrope), `AppFonts.mono` (JetBrains Mono)
- Spacing: `AppSpacing` (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32)
- Radius: `AppRadius` (md=8, lg=12)
- Text sizes: `AppTextStyles` (xs=12, sm=14, md=16, lg=18, xl=22, xxl=30)

Positioning follows the `spacing-and-alignment` skill: insets are measured from a control's **box** (padding + border), not its text — so a chip replacing a bare icon in a slot takes a different offset — and centered content centers on the **screen**, never on the gap left between the surrounding controls.

## Key Conventions

1. **Auto-commit while typing** — real set rows commit on every keystroke (onChanged), so navigating away can never lose a value; blur commit remains as a safety net. Draft rows commit on blur only (a keystroke must not materialize a draft mid-typing), and are flushed on app lifecycle pause/inactive/detached, exercise-tab switch, wizard page change, and session end (rows register commit handles with the VM).
2. **Numeric-only input** — live/history weight+reps cells use `FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))`; planned cells allow ranges (`[0-9.\-\s]`).
3. **Draft rows (freestyle only)** — virtual rows that insert a fresh set on commit; a draft materializes on any user-entered value (weight, reps, variation, or notes). Planned rows are real rows from materialization — there is NO empty-row filling (that heuristic landed data on the wrong row).
4. **Swipe-to-reveal** — SwipeActions for Duplicate/Delete; delete is immediate.
5. **Lessons modal is polymorphic** — takes a `Listenable` + callbacks, works with both VM patterns.
6. **Exercise order** — planner reorder persists to `dim_planned_session_exercise.exercise_order`; session reorder persists to `fact_session_exercise.exercise_order` (a real column — the old JSON blob is gone) and restores on hot restart; the logs viewer orders by the same column.
7. **History** — `groupHistoryByExercise` from `session_local_state.dart`; read-only in planner/logs, editable with a confirmation gate only in the live session.
8. **initState defer** — VM methods that mutate `ValueNotifier` state synchronously must run post-frame via `WidgetsBinding.instance.addPostFrameCallback`.
9. **Supersets retired (2026-08-14, column dropped 2026-08-24)** — no UI creates or emphasizes supersets, and `superset_group_number` no longer exists (schema v2). Dormant slot support in the live session VM remains; a restored multi-exercise slot renders as its first exercise.
10. **Preview mirrors the session UI** — `_SessionPreview` is a read-only adapter over the shared card/row, not a hand-rolled layout.
11. **One text box, two halves** — editable text boxes are `LambdaInput` (the Pre-Evaluation notes field is the reference; dense search boxes are `LambdaSearchField`), read-only text boxes are `LambdaReadout` (the past-session viewer's display is the reference). A box's fill is one tier above its ground — `surface` on the page, `surfaceHigh` on a card or default sheet (`elevated: true`; 2026-10-08). Exceptions: inline header titles that ARE the header (chrome-less tap-to-rename), numeric cells (set grid — mono, centred), and the exercise card's review note box, which copies the Pre-Evaluation field by name — base fill, no step up (2026-10-08). Rule: `frontend-design` §6.

## Toolchain & Diagnostics

- **The dev flow lab** (`lib/features/dev/lab/`, the "Flow Lab" card on the dev screen) runs the REAL program screens against a sandbox PowerSync database seeded with fake data — `lambda_lab.db` beside the app's own, **never connected**, so nothing it does reaches Supabase. Three moving parts: `swapDatabase` points the global `ps.db` at the sandbox (and hands the app's own back on the way out), `labMode` makes the two REST-first repos (`ProgramRepository`, `ProgramRunRepository`) take local-only remotes, and `lab_seed.dart` builds the world through those same real repositories. It is a top-level route (`/dev/lab`, outside the shell) because the shell's tabs must not be reachable while the app is on the sandbox; the library's push of a program's detail is the one call that switches paths on `labMode`. Opening seeds only what is missing; the header's reset wipes the sandbox and re-seeds. The swap is **holder-counted** (`enter`/`leave` per mounted lab screen, 2026-10-08): overlapping lab screens are real — a pushed second copy disposes first — and before the count, that dispose handed the app's real database back under the lab that stayed open, which is how a review built in the lab reached the user's account.
- **If a release build on device misbehaves but debug works, start from `docs/release_only_crashes.md`** — not from app code. Release/AOT and Debug/JIT are different compilers, so those bugs are usually in the build, not the feature. The `release-crash-triage` skill (`.claude/skills/`) carries the step-by-step checklist.
- **Watch for `+eol` packages** (`grep eol pubspec.lock`). A `+eol` version means a retired mechanism the current toolchain has moved past — that is what broke the 2026-09-30 release build (fixed by `powersync ^1.8.0 → ^2.4.0`, no Dart changes needed).
- **iOS/Xcode 27 build constraints** (pod module verification, deployment-target floor, simulator lipo) are documented in the `ios-toolchain-xcode27` memory.
- **Installing a build on a device via `devicectl` wipes its local database** — flag that to the user before doing it, since unsynced writes are lost.
