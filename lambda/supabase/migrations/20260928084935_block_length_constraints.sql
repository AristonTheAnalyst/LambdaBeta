-- A block is measured one way, and sessions mode has no calendar end.
--
-- Both rules exist because the block now owns its length. The editor used to
-- offer Weeks and Sessions as two independent numbers, so a block could claim
-- both and mean neither; now the block's length is the single answer to "is
-- this phase over?", and that only works if there is exactly one answer to read.
--
-- Constraints only, on columns that already exist: no new table, so no PowerSync
-- stream change and no dashboard step. A violation on upload surfaces as a
-- quarantined 23514 in `upload_failures` — which is the point, but it should
-- never happen: `ProgramRepository.updateBlock` normalises the same two rules at
-- the only place these columns are written, so they are unreachable from the app.

-- Weeks XOR sessions. `num_nonnulls` rather than a boolean expression so the
-- intent reads as the rule rather than as a truth table.
alter table public.dim_program_block
  add constraint dim_program_block_length_check
  check (num_nonnulls(target_weeks, target_sessions) <= 1);

-- Sessions mode has no calendar end. The block ends when the sessions are done,
-- and the user is asked to confirm it — an end date here would be a second,
-- competing answer to the same question.
alter table public.dim_program_block
  add constraint dim_program_block_sessions_no_end_check
  check (target_sessions is null or end_date is null);

-- `Ends` is `Starts` + weeks, so an end with no start is a projection of
-- nothing. The editor cannot produce the shape either: its Ends field is inert
-- until Starts is set.
alter table public.dim_program_block
  add constraint dim_program_block_end_needs_start_check
  check (end_date is null or start_date is not null);
