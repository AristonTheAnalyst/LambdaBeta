# PR Methodology

How personal records are computed in Lambda. PRs are **fully derived on
read** — there is no PR table; every surface recomputes from the set
history (`fact_session_exercise_set` joined through
`fact_session_exercise`), so editing or deleting a set changes every PR
view on the next read with nothing to clean up.

## The definition: a set is a PR iff it extends the best-ever frontier

Per **(exercise × variation)** pair (null variation is its own distinct
key), a set `(w, r)` is a PR iff **no prior set did at least r reps at at
least w weight**:

```
PR(set) ⇔ ¬∃ prior (w' ≥ w ∧ r' ≥ r)
```

That single dominance check covers both directions of the weight/reps
relation at once — they are the same thing viewed from opposite sides.
Consequences, all intended:

| Case | Verdict |
|---|---|
| 105×3 after 100×3 | PR (more weight, same reps) |
| 100×5 after 110×1 | PR (110 doesn't cover 5 reps) |
| 110×1 after 110×2 | not a PR (dominated) |
| 100×4 after 100×5 | not a PR (dominated) |
| identical repeat | not a PR |
| first-ever set on a pair | PR ("First PR") |

Bodyweight is just weight 0. One set = **one `PrEvent`**, even when it
beats prior records on both dimensions at once — a single 100×10 after
6×10 and 100×3 is ONE PR, not two.

## Before-facts

Each event carries the previous frontier values it beat, one per
dimension:

- `beforeWeight` — previous best weight at ≥ r reps ("was 6 × 10")
- `beforeReps` — previous best reps at exactly w ("was 100 × 3")

Both null = first PR. The end screen renders both facts when both exist
(`was 6 × 10 · 100 × 3`): one PR can beat two previous PRs, and both are
real achievements. A set can beat at most two — the frontier is a
monotone staircase.

Dominated sets still update the frontier maps: 90×6 after 100×6 is not a
PR, but a later 90×8 must report "was 90 × 6", never a first.

## Counts and accents

Every count, badge, accent, and modal uses **events**: the live stats
bar, the logs summary, the pills, and the insights totals all count the
same thing, so they can never disagree. (The pre-2026-08-29 engine
counted per-axis records — one 105×3 set was 3 PRs in the logs summary
and 1 in the live stats bar. The frontier model makes the honest single
number the only number.)

## Lenses — projections live in insights, never in detection

Everything axis-shaped is a pure projection over raw set history, not
over events, and never gates what IS a PR:

- `repMaxCurve(sets)` — `curve[N]` = highest weight with ≥ N reps, for
  ANY N (the `kTrackedRepCounts` list is a display config for the
  insights curves only). 110×2 feeds the 3-rep lens through any later
  ≥3-rep set even though it was never a "3RM PR".
- `weightMaxCurve(sets)` — most reps at each exact weight. No
  propagation: 100×10 does not invent a 10-rep entry at 5kg (the exact
  weight lens is exact; the ≥-direction is the rep-max lens's job).
- `repAxisHistory(sets, n)` / `weightAxisHistory(sets, w)` — the
  chronological progression of one axis ("5RM history"), powering the
  insights axis-history sheets.

These lenses replaced the old per-axis record types (`PrType.repMax` /
`weightMax`), propagation records (`isPropagated`), and the
`achievedRecords` / `countableRecords` filters — all deleted 2026-08-29.

## Engine

- `lib/features/session/model/pr_engine.dart` — `prEvents` (frontier
  walk) + the lenses.
- `lib/features/session/model/pr_service.dart` — memoized derivation
  over the set timeline; `invalidate()` after any set write.
- Live sessions fold their in-memory sets into the walk in
  `_recomputePRs`; the logs viewer does the same over history + the
  viewed session.

## Historical note

The pre-2026-08-29 engine created one record per improved axis (rep-max
at tracked N values, weight-max), tagged propagated records, and the
`fact_pr` table persisted snapshots until it was dropped 2026-08-14 in
favor of derivation on read.
