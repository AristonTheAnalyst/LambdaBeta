# PR Methodology

How personal records are computed, persisted, and cleaned up in Lambda.

## The core insight: a set is PR on multiple axes at once

A single set of `105kg × 3` can be a PR for **several rep-max records at the
same time**. If your previous best at 3 reps was 100kg, then 105×3 also beats
your previous 1RM and 2RM (if you can lift 105 for 3, you can lift it for 1
or 2). One set → several PR records.

The engine (`lib/features/session/model/pr_engine.dart`) walks the full set
history chronologically, maintaining a **rep-max curve** per exercise
(`curve[N]` = best weight ever lifted for ≥ N reps). Every set is checked
against the curve at each rep count N from 1 to the set's reps; any N the
set improves generates a record.

## The PR axes

| Axis | Definition | Example |
|---|---|---|
| **Absolute PR** | Best weight × reps for an exercise, any variation, any rep count. `weight > best` or (`weight == best` and `reps > best`). | "Bench: 100kg × 8" |
| **Rep-max (N-rep max)** | For each rep count N, the highest weight lifted for ≥ N reps. One set improves 1RM…N RM simultaneously. | "New 3RM: 105kg" |
| **Weight-class** | Most reps ever done at a given weight for an exercise. | "Most reps at 100kg: 8" |
| **Per-exercise** | Any of the above filtered to a single exercise. | Bench's absolute PR |
| **Exercise × variation** | Any of the above filtered to one exercise + variation pair. | Best incline bench vs flat bench |

## Persistence: fact_pr snapshots

PRs are **persisted, not derived on every read**. They live in `fact_pr` as
**self-contained snapshots**:

- Each row copies its values (exercise, variation, weight, reps, type, date,
  `workout_set_id`) at write time.
- `workout_set_id` is a **plain column, not a foreign key** — a PR snapshot
  must survive the source set being deleted or edited.
- Deleting/editing a set does **not** retroactively erase the achievement:
  you physically lifted that weight that day.

### Write paths

1. **Session ends** (`SessionViewModel.endWorkout`): the session's PRs are
   computed against prior history and inserted into `fact_pr`.
2. **Past-session edit** (`WorkoutDetailViewModel`): editing/adding/duplicating
   a set recomputes that exercise's `fact_pr` records from remaining valid
   history (delete + re-insert for that exercise only). A set edited down stops
   being a PR; a set edited up to beat the baseline becomes one.
3. **Backfill**: the PR library, on first load for a user with no `fact_pr`
   rows, derives the full timeline once from set history and persists it.

## Deleting a set that holds PRs

Two delete semantics — the app prompts when a set has PR records:

- **Delete set only** — set gone, `fact_pr` rows stay. For "I did lift that,
  keep the achievement."
- **Delete set + its PRs** — set gone, its `fact_pr` rows removed, then the
  exercise is **recomputed** from the remaining valid history. This promotes
  the next-best record: deleting a typo'd 2000kg 1RM promotes the 180kg 1RM
  back into the table. For "that 2000kg squat was a typo, clean it up."

Sets with no PR records delete immediately (no prompt).

## Live-session detection vs fact_pr

During a live session, per-row PR highlighting uses the in-memory derived
baseline (`prevBestByExercise` from `_pastSets`) for speed. This stays
consistent with `fact_pr` because `fact_pr` is written at `endWorkout` from
the same history. Keep these two in agreement — don't change one without the
other.

## Source

- Engine: `lib/features/session/model/pr_engine.dart`
- Persistence: `lib/data/repositories/pr_repository.dart`
- Table: `fact_pr` (migration `20260731100001_create_fact_pr.sql`)
- Library UI: `lib/features/session/view/pr_library_screen.dart`
