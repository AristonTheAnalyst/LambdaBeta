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

Naming rules (2026-08-13 redesign): `dim_*` = reference data (soft-deleted via `is_archived`); `fact_*` = events. "Workout" language is banned in the DB — templates are **planned sessions**, logged workouts are **sessions**. See the `app-features` skill for the complete table inventory, RLS matrix, and sync wiring; the `sync-contract` skill for schema/sync changes.

## Core Architecture: The Three Session Screens

The app has three session surfaces that share one UX. **The live session screen is the primary design foundation** — the other two mirror its patterns via shared widgets (see the `session-ux-consistency` skill for the rules).

### 1. Session Screen (`lib/features/session/`) — Active Training

**Purpose:** Log a live workout in real-time. The most feature-rich screen.

**Structure:**
- `view/session_screen.dart` — `SlidePages` wizard: page 0 = Prep (feeling/notes/start + last-session reflection), page 1 = Training (active workout), page 2 = Reflection (before/after recap). Training page idle state shows `_SessionTemplateCard` (template picker) + `_SessionPreview` (read-only planned preview).
- `viewmodel/session_viewmodel.dart` — `SessionViewModel`, a `ChangeNotifier` with mutable fields (NOT an immutable state class).
- `view/live_exercise_card.dart` — `LiveExerciseCard`, a thin adapter over the shared `SessionExerciseCard`/`SessionSetRow`.
- Renders: `SessionExerciseCard` (with `ExerciseSelector` pills, pinned lesson, Lessons/History/PRs pills) → `SessionSetRow` grid + rest timer + stats bar.

**Key features (priority order):**
- Exercise selector (pill popover: switch, arrows reorder, add, hold-to-delete X)
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
- Prep page: planned banner, feeling picker (1-5), pre-notes, Start button
- End Workout modal: feeling picker, post-notes

### 2. Planner Screen (`lib/features/programs/view/plan_session_screen.dart`) — Planned Session Editor

**Purpose:** Plan a future session (template) inside a Program, or standalone.

**Structure:**
- Pushed via `MaterialPageRoute` from `program_detail_screen.dart`
- Shares the same `ProgramDetailViewModel` (constructor param)
- `ProgramDetailState` — immutable `ValueNotifier` with `copyWith`
- `_PlanExerciseCard` — adapter over the shared `SessionExerciseCard`; rows use `SessionSetRow` mode `planned` (free-text targets)

**Key features:**
- Editable inline header (tap to rename, auto-commit on blur), session notes
- Day-of-week picker (calendar-mode programs only)
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
| `Program` | `dim_program` | A program containing planned sessions (no progression mode) |
| `ProgramRun` / `ProgramProgress` | `fact_program_run` | Active program tracking (carries `progression_mode`) |

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
| `session_exercise_card.dart` | All three screens | THE exercise card (selector + pinned lesson + pills + sets grid). Null callbacks grey/hide controls. |
| `session_set_row.dart` | All three screens | THE set row — `SetRowMode { live, planned, history }` + flags (`isPr`, `readOnly`, `plannedTarget`); registers a commit handle for lifecycle flushes. |
| `exercise_selector.dart` | All three screens | Pill popover: switch / arrows reorder / add / hold-to-delete X. |
| `exercise_tab_chip.dart` | `ExerciseSelector` | The pill itself. Active color is accent everywhere. |
| `card_pill_button.dart` | `SessionExerciseCard` | Lessons/History/PRs pill chrome. |
| `swipe_actions.dart` | Set rows | Swipe-to-reveal Duplicate/Delete. |
| `stats_row.dart` | All three screens | StatsRow + StatsTile. |
| `page_header.dart` | All screens | Standard app header bar. |
| `glass_button.dart` | All screens | Accent outline button. |
| `segmented_control.dart` | Program screens | Day-of-week picker, mode toggle. |
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
- `PlannedSessionRepository`: fetchPlannedSessions (standalone or via program links), fetchPlannedSessionById, fetchPlannedExercises, fetchPlannedSets, createPlannedSession, updatePlannedSession, deletePlannedSession (archives + its groups/sets, hard-deletes links), createPlannedExercise, deletePlannedExercise, createPlannedSet, updatePlannedSet, deletePlannedSet, consolidateDuplicateExerciseGroups, duplicatePlannedSession, swapExerciseOrders, renumberExerciseOrders, fetchProgramLinks, createProgramLink, updateProgramLink, deleteProgramLink
- `ProgramRepository`: fetchPrograms, fetchProgram, createProgram, updateProgram, deleteProgram (archives + hard-deletes links), fetchPlannedSessions(programId), fetchPlannedSessionSets, duplicatePlannedSession, fetchProgramWithSessions, duplicateProgram, fetchGoals, createGoal, deleteGoal
- `ProgramRunRepository`: getCurrentRun, startProgramRun (takes progressionMode), updateRunConfig, endCurrentRun, fetchProgramHistory, getNextPlannedSession (from run mode + join rows), getProgress
- `ExerciseRepository`: fetchExerciseDetailMap, fetchVariations, findExerciseByName, createExercise, reactivateExercise, findVariationByName, createVariation, reactivateVariation, deactivate/update variants
- `LessonRepository`: fetchLessons, createLesson, updateLesson, setPinned, deleteLesson

## PR Methodology

PRs are **fully derived on read** — there is no PR table. On every relevant read, the engine (`lib/features/session/model/pr_engine.dart`, used via `pr_service.dart` / `_recomputePRs`) walks logged `fact_session_set` history chronologically:

- **Axes**: rep-max (`curve[N]` = best weight for ≥ N reps, N ∈ 1–10, 12, 15, 20, 25, 30) and weight-max (most reps at an exact weight). One set can be a PR on many axes at once (105 × 3 improves 1RM, 2RM, 3RM).
- **Scope**: per (exercise × variation) — null variation is its own key. Bodyweight is just weight 0 — it feeds the curve like any other weight (a 13-rep dips set is a 12RM at 0kg). Reps that fall between tracked values claim the highest tracked value below them as the explicit record (13 reps → explicit 12RM); lower tracked Ns stay propagated.
- **Propagation**: heavier lifts bump implied records on lighter axes, but only for weights the user has actually lifted — nothing is fabricated.
- **Edit-past-data self-heals**: correcting a set removes its derived PRs on the next read; no stale rows to clean up.
- **Display & counting rules (2026-08-26)**: propagated records appear nowhere (`achievedRecords`); weight-max records (bodyweight 0kg included) are display-only — counts, badges, session totals, and insights charts use explicit rep-max only (`countableRecords`).

Full spec: `docs/pr_methodology.md` (note: its "snapshot rows in fact_pr" sections are historical — the table was dropped 2026-08-14).

## Design Tokens

- Colors: `AppColors` (bg, surface, surfaceHigh, primary, accent, accentBg, accentText, muted, border, success, successBg, danger, dangerBg, history, historyBg, planned, plannedBg)
- Fonts: `AppFonts.ui` (Manrope), `AppFonts.mono` (JetBrains Mono)
- Spacing: `AppSpacing` (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32)
- Radius: `AppRadius` (md=8, lg=12)
- Text sizes: `AppTextStyles` (xs=11, sm=13, md=15, lg=17, xl=20, xxl=28)

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
