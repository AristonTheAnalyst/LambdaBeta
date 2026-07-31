# PR Methodology

How personal records are computed, persisted, and cleaned up in Lambda.

## The core insight: a set is a PR on multiple axes at once

A single set of `105kg × 3` can be a PR for **several rep-max records at the
same time**. If your previous best at 3 reps was 100kg, then 105×3 also beats
your previous 1RM and 2RM (if you can lift 105 for 3, you can lift it for 1
or 2). One set → several PR records. A PR isn't a set — it's an **axis
improvement**: one set can be the reason several PRs exist.

The engine (`lib/features/session/model/pr_engine.dart`) walks the full set
history chronologically, maintaining a **rep-max curve** per exercise
(`curve[N]` = best weight ever lifted for ≥ N reps). Every set is checked
against the curve at each rep count N from 1 to the set's reps; any N the set
improves generates a record.

## The PR axes

| Axis | Definition | Example |
|---|---|---|
| **Rep-max (N-rep max)** | For each rep count N, the highest weight lifted for ≥ N reps. One set improves 1RM…N RM simultaneously. | "New 3RM: 105kg" |
| **Weight-max** | Most reps ever done at a given weight for an exercise. Kept distinct in the DB from rep-max so querying per axis is simple. | "Most reps at 100kg: 8" |
| **Per-exercise** | Any of the above filtered to a single exercise. | Squat's 5RM |
| **Exercise × variation** | Any of the above filtered to one exercise + variation pair. | Best incline bench vs flat bench |

There is **no "absolute" PR** — the axes above are the complete set.

## Persistence: fact_pr snapshots

PRs are **persisted** in `fact_pr` as snapshots. Each row copies its values
(exercise, variation, weight, reps, type, date, `workout_set_id`) at write time.

`workout_set_id` is a **plain column, not a foreign key** — it records *which
set caused the PR*, but the row is self-contained.

### Write paths

1. **Session ends** (`SessionViewModel.endWorkout`): the session's PRs are
   computed against prior history and inserted into `fact_pr`. Nothing is
   committed until the workout is actually done — while the user is logging
   sets they just get live PR highlights, not fact_pr writes.
2. **Past-session edit** (`WorkoutDetailViewModel`): editing/adding/duplicating
   a set recomputes that exercise's `fact_pr` records from current data. The
   recompute is in-memory and scoped to one exercise (microseconds) — it only
   regenerates that exercise's rows, not the whole table. This is why editing
   a set up makes it a PR and a set edited down stops being one, with instant
   row highlighting in the past-session viewer.
3. **Backfill** (`PrRepository.loadAllWithBackfill`): if `fact_pr` is empty,
   the first visit to the PR library or Dev catalog derives the full timeline
   once from set history and persists it.

## Deleting a set: cascade + recompute

Deleting a source set **always deletes its PRs** — the set was the reason they
existed. There is no "keep the achievement" option. The app shows a warning:
"This set holds N PR records, which will be deleted too."

After deletion, the exercise is **recomputed from the remaining valid data**,
which promotes the next-best record. Example: you did 150kg 1RM, then 170kg,
then 160kg (160 was never a PR while 170 existed). Delete the 170 set → its PRs
go → recompute from {150, 160} → **160 becomes the 1RM**, because it beat 150
when it was done. The recompute-from-remaining is the correct semantics, not
"jump to the previous PR."

A mid-session PR that is later beaten within the same session does not persist —
only the day's best matters.

## Live-session detection vs fact_pr

During a live session, per-row PR highlighting uses the in-memory derived
baseline (`prevBestByExercise` from `_pastSets`) for speed. This stays
consistent with `fact_pr` because `fact_pr` is written at `endWorkout` from
the same history. Keep these two in agreement — don't change one without the
other.

## Source

- Engine: `lib/features/session/model/pr_engine.dart`
- Persistence: `lib/data/repositories/pr_repository.dart`
- Table: `fact_pr` (migration `20260731100001_create_fact_pr.sql`; redesign
  `20260731110001_pr_redesign.sql`)
- Library UI: `lib/features/session/view/pr_library_screen.dart`
