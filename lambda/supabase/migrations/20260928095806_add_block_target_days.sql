-- 2026-09-28: a block's calendar length can carry a remainder of days.
--
-- A phase is not always a whole number of weeks. "Three weeks and a four-day
-- taper", "eleven days off" — those are real, and until now the only way to say
-- one was to round. The rounding was not cosmetic: `end_date` is a PROJECTION of
-- the length, so a block that really ended on a Wednesday stored the following
-- Saturday, and every reader downstream (the finish check, the banner, the
-- countdown) agreed on the wrong day.
--
-- So `target_days` is a remainder, not a third unit. It belongs to the weeks
-- length the way `%` belongs to `~/`: `target_weeks: 8, target_days: 3` is ONE
-- length of 59 days, and NULL means "no remainder" rather than "zero days" —
-- the same null-means-absent idiom every other column here follows.
--
-- CONSTRAINT ONLY, plus one nullable column: no new table, so no PowerSync
-- stream change and no dashboard step (and every stream is `SELECT *`, so the
-- column downloads on the next sync with nothing to deploy).

alter table public.dim_program_block add column if not exists target_days integer;

comment on column public.dim_program_block.target_days is
  'Days remainder of the weeks length, 0..6. NULL = no remainder. Part of '
  'target_weeks, never a length of its own: a run''s end date is '
  'start_date + target_weeks*7 + coalesce(target_days, 0).';

-- ── The one destructive step, and why it is not a loosening ────────────────
-- The create-table migration declared this inline on the column:
--
--     target_weeks integer check (target_weeks is null or target_weeks > 0)
--
-- which forbids the exact shape a sub-week block needs: `0 weeks 3 days`. The
-- rule moves to the TOTAL, which is what a length actually is. The replacement
-- is strictly stronger than the check it replaces — it also rejects
-- `0 weeks 0 days`, which the old one accepted — so nothing is being relaxed.
alter table public.dim_program_block
  drop constraint if exists dim_program_block_target_weeks_check;

-- coalesce on both terms so the expression is a definite boolean in every case
-- rather than NULL (which a CHECK would accept) when only one column is set.
alter table public.dim_program_block
  add constraint dim_program_block_length_positive_check
  check (
    (target_weeks is null and target_days is null)
    or coalesce(target_weeks, 0) * 7 + coalesce(target_days, 0) > 0
  );

-- A remainder is a remainder. A value above 6 is a second way to say weeks, and
-- two spellings of one length is the thing this column exists to avoid.
alter table public.dim_program_block
  add constraint dim_program_block_days_range_check
  check (target_days is null or target_days between 0 and 6);

-- Days with no weeks to remain from is a value nothing can read — an end date
-- projected from a remainder alone would be a length with no phase to attach it
-- to. Same argument as dim_program_block_end_needs_start_check.
alter table public.dim_program_block
  add constraint dim_program_block_days_need_weeks_check
  check (target_days is null or target_weeks is not null);

-- NO CHANGES to any existing policy, grant or stream: the column is nullable
-- and additive, and every sync stream selects `*`.
