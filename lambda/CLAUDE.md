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
│   ├── programs/            # Program + planned workout editor
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

## Core Architecture: The Three Workout Screens

The app has three distinct workout screens that share a common UX. **The session screen is the primary design foundation** — the other two mirror its patterns.

### 1. Session Screen (`lib/features/session/`) — Active Training

**Purpose:** Log a live workout in real-time. This is the most feature-rich screen.

**Structure:**
- `session_screen.dart` — Uses `SlidePages` (page 0 = start/"Mental Prep", page 1 = active workout)
- `SessionViewModel` — `ChangeNotifier` (mutable fields, `notifyListeners()`)
- State is stored as mutable fields on the ViewModel (NOT an immutable state class)
- Renders: `ExerciseTabBar` → `ExerciseCard` → `SessionSetRow` grid + `RestTimerBar` + `SessionStatsBar`

**Key features (in priority order):**
- Exercise tab bar (chips, long-press reorderable, superset hexagon icons, set count badges)
- Exercise card: PLANNED/UNPLANNED badge, PR count badge, lesson bar, history picker
- Inline editable set grid: KG/REPS/VARIATION/NOTE columns, `SessionSetRow` with:
  - `FilteringTextInputFormatter` for numeric-only weight/reps
  - Auto-commit on blur (weight/reps)
  - Ghost planned-target overlay (green tint from PlannedSet)
  - PR accent row (background + border turn accent)
  - Swipe-to-duplicate, swipe-to-delete
  - Variation dropdown with "Did you mean?" dedup + inline create-new
  - Notes icon modal
- Stats bar: SETS / PRS (tappable → PR modal) / EXERCISES / AVG REST
- Rest timer bar + hold-to-finish End Workout
- Pre-workout start page: planned banner, feeling picker (1-5), pre-notes, Start button
- End Workout modal: feeling picker, post-notes

### 2. Planner Screen (`lib/features/programs/view/plan_workout_screen.dart`) — Planned Workout Editor

**Purpose:** Plan a future workout inside a Program. Completed planned workouts become session workouts.

**Structure:**
- Pushed via `MaterialPageRoute` from `program_detail_screen.dart`
- Shares the same `ProgramDetailViewModel` (via constructor param)
- `ProgramDetailState` — immutable `ValueNotifier` with `copyWith`

**Key features:**
- Editable inline header (tap to rename workout, auto-commit on blur)
- Session Notes field
- Day-of-week picker (calendar-mode programs only)
- Stats bar: SETS / EXERCISES (2 tiles — no PRs/rest since no live data)
- Exercise tab bar (long-press reorderable), exercise card, `PlanSetRow` grid
- `PlanSetRow` mirrors `SessionSetRow` exactly but bound to `PlannedSet` (target fields)
- Lessons/History per exercise (same modal reuse)
- Add exercise modal (single-exercise only — no superset)
- Save button (appears when dirty) + auto-commit on blur
- Delete workout with confirmation dialog

**What's deliberately excluded (can't exist for planning):**
- PRs (no logged data), rest timer (no live workout), feeling picker, PLANNED badge
- Ghost planned-target values (the fields themselves ARE the plan targets)

### 3. Past-Session Viewer (`lib/features/logs/view/workout_detail_screen.dart`) — Completed Workout

**Purpose:** Review and edit a completed workout from Training Logs.

**Structure:**
- Navigated to via go_router from `LogsScreen` (`/logs/:workoutId`)
- `WorkoutDetailViewModel` — `ValueNotifier<WorkoutDetailState>` (immutable state class)
- Has two modes: **view** (read-only) and **edit** (inline editing)

**Key features:**
- Same tabbed exercise-card layout as session/planner
- 4-tile stats bar: SETS / PRS / EXERCISES / AVG REST
- PR detection via `isPr()` from `session_local_state.dart`
- PLANNED/UNPLANNED badge (from `workout.plannedWorkoutId`)
- PR count badge on exercise header
- Pre-workout feeling display (1-5 indicators)
- Inline editing in edit mode: same `SessionSetRow`-like rows with swipe actions
- Add exercise + "+ ADD SET" in edit mode
- Pre/Post notes in footer bar (edit mode only)
- Lessons/History per exercise (same shared modals)

**What's excluded:**
- Rest timer (no rest data stored per-workout)
- Elapsed timer (no end timestamp stored)
- Superset display (sets have supersetGroupNumber but display not implemented)
- Ghost planned-target overlay (would need planned sets context at load time)

## Data Models

### Core workout models (`lib/data/models/`)

| Model | DB Table | Purpose |
|---|---|---|
| `Workout` | `fact_workout` | A completed/active workout session |
| `WorkoutSet` | `fact_workout_set` | One logged set within a workout |
| `PastSetRow` | extends WorkoutSet | Adds `workoutCreatedDate` for history timeline |
| `PlannedWorkout` | `dim_planned_workout` | Template for a planned workout inside a program |
| `PlannedSet` | `dim_planned_set` | Target set within a planned workout |
| `ExerciseDetail` | `dim_exercise` + bridge | Exercise with its assigned variations |
| `CustomVariation` | `dim_variation` | A variation (e.g. "Incline", "Paused") |
| `Lesson` | `fact_lesson` | Per-exercise text cue/prompt |
| `Program` | `dim_program` | A program containing planned workouts |
| `ProgramRun` / `ProgramProgress` | `program_run` | Active program tracking |
| `RestPeriod` | `fact_rest` | Logged rest periods during a session |

### Key model fields

```
Workout: workoutId, userId, createdDate, isActive, preNotes, postNotes, preFeeling,
         programId, plannedWorkoutId, plannedWorkoutName

WorkoutSet: setId, workoutId, exerciseId, variationId, setNumber, weight, reps (List<num>),
            duration (List<num>), notes, exerciseName, variationName, supersetGroupNumber

PlannedSet: plannedSetId, plannedWorkoutId, exerciseId, variationId, setNumber,
            exerciseSequenceOrder, targetWeight, targetReps, targetDuration, targetNotes

PlannedWorkout: plannedWorkoutId, programId, name, notes, sequenceOrder, dayOfWeek
```

### Workflow: Plan → Log → Review

```
Program → PlannedWorkout → PlannedSet
             │
             ▼ (session_start creates Workout + links plannedWorkoutId)
Active Session → Workout → WorkoutSet (logged, may link plannedSetId)
             │
             ▼ (workout ends, is_active = 0)
Completed Workout → Training Logs (review/edit)
```

## ViewModel Patterns

There are two patterns used:

1. **`ChangeNotifier`** (mutable state, `notifyListeners()`):
   - `SessionViewModel` — only one. Uses mutable fields directly.

2. **`ValueNotifier<State>`** (immutable state, `copyWith()`):
   - `ProgramDetailViewModel` with `ProgramDetailState`
   - `WorkoutDetailViewModel` with `WorkoutDetailState`
   - `LogsViewModel` with `LogsState`

**Rule of thumb:** If the state struct is complex and needs selective rebuilds, use immutable state. If the logic is tightly coupled with many derived properties, ChangeNotifier is OK (session screen).

## Shared Widgets (`lib/shared/widgets/`)

| Widget | Used By | Purpose |
|---|---|---|
| `swipe_actions.dart` | SessionSetRow, PlanSetRow, _DetailSetRow | Swipe-to-reveal Duplicate/Delete |
| `exercise_tab_chip.dart` | All three screens | ExerciseTabChip + AddExerciseButton |
| `stats_row.dart` | session_stats_bar, _PlanStatsBar, _WorkoutBody | StatsRow + StatsTile |
| `page_header.dart` | All screens | Standard app header bar |
| `glass_button.dart` | All screens | Accent outline button |
| `segmented_control.dart` | Program screens | Day-of-week picker, mode toggle |
| `dropdown_select.dart` | All set rows | Variation picker with search + create-new |
| `slide_up_modal.dart` | Add exercise, notes, pickers | Bottom sheet modal (showLambdaModal) |

## Shared Modals (from `lib/features/session/view/`)

| Modal | Imported By | Pattern |
|---|---|---|
| `lessons_modal.dart` | All exercise cards | Takes `Listenable` + callbacks (not concrete VM) |
| `notes_modal.dart` | All set rows | Simple state-less function |

## Repository Layer (`lib/data/repositories/`)

Each repository wraps PowerSync SQLite CRUD. Key methods:

- `WorkoutRepository`: createWorkout, endWorkout, cancelWorkout, insertSet, updateSet, deleteSet, loadSetsForWorkout, loadWorkoutsWithSets, loadPastSetsTimeline, fetchWorkout, findLastSetForExercise
- `ProgramRepository`: fetchProgram, fetchPlannedWorkouts, createPlannedWorkout, updatePlannedWorkout, archivePlannedWorkout, fetchPlannedSets, createPlannedSet, updatePlannedSet, archivePlannedSet, swapPlannedExerciseOrders, reorderPlannedWorkouts
- `ExerciseRepository`: fetchExerciseDetailMap, findExerciseByName, createExercise, reactivateExercise, fetchVariations, findVariationByName, createVariation, reactivateVariation, addBridge, fetchBridges
- `LessonRepository`: fetchLessons, createLesson, toggleLessonPin, deleteLesson
- `PrRepository`: insertPrs, loadAll, loadForWorkout, loadForSets, deleteForSets, deleteForExercise, count

## PR Methodology

**See `docs/pr_methodology.md` for the full spec.** Summary:

- PRs are persisted as **self-contained snapshots** in `fact_pr` (no FK to the
  source set — achievements survive set deletion).
- **One set can be a PR on multiple axes**: `105kg × 3` simultaneously improves
  1RM, 2RM, and 3RM (rep-max curve semantics). The engine
  (`lib/features/session/model/pr_engine.dart`) walks history chronologically
  maintaining `curve[N]` = best weight for ≥ N reps.
- Axes: **absolute** (best weight×reps), **rep-max** (best weight for N reps),
  **weight-class** (most reps at a weight), **per-exercise**, **exercise×variation**.
- Written at `endWorkout`; past-session edits recompute the edited exercise.
- Deleting a set that holds PRs prompts: **"Set only"** (keep achievement) or
  **"Set + PRs"** (remove + recompute, promoting the next-best — the poison-cleanup
  path for typos like a 2000kg squat).

## Design Tokens

- Colors: `AppColors` (bg, surface, surfaceHigh, primary, accent, accentBg, accentText, muted, border, success, successBg, danger, dangerBg, history, historyBg)
- Fonts: `AppFonts.ui` (Manrope), `AppFonts.mono` (JetBrains Mono)
- Spacing: `AppSpacing` (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32)
- Radius: `AppRadius` (md=8, lg=12)
- Text sizes: `AppTextStyles` (xs=11, sm=13, md=15, lg=17, xl=20, xxl=28)

## Key Conventions

1. **Auto-commit on blur:** Weight/reps fields save on focus loss, not on an explicit Save button. The planner also has a Save button for explicit batch persisting.
2. **Numeric-only input:** Weight/reps cells use `FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))`
3. **Draft rows:** Adding a set creates a local-only draft row. It becomes a real set when reps are entered and the field loses focus.
4. **Swipe-to-reveal:** SwipeActions widget for Duplicate/Delete — no confirmation dialog for delete (immediate).
5. **Lessons modal is polymorphic:** Takes a `Listenable` + callbacks, not a concrete ViewModel type. Works with both `ChangeNotifier` and `ValueNotifier`.
6. **Reorderable exercise tabs:** Long-press drag to reorder (when 3+ tabs). Uses `ReorderableDragStartListener` (instant touch-activation).
7. **History:** Uses `groupHistoryByExercise` from `session_local_state.dart`. Read-only in planner and past-session viewer; editable with confirmation gate only in session history view.
8. **initState defer:** Viewmodel methods that mutate `ValueNotifier` state synchronously must be called after the first frame via `WidgetsBinding.instance.addPostFrameCallback` to avoid `setState() during build`.
