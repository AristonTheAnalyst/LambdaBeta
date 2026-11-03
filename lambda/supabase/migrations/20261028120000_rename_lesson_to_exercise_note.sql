-- Naming coherence (2026-10-28)
--
-- The UI has called a per-exercise cue an EXERCISE NOTE since 2026-10-23; the
-- table and its columns still carried the retired word "lesson" (a leftover
-- from the 2026-08-13 redesign). This is a pure rename: no data moves, and
-- the table stays in the `powersync` publication — membership is by table
-- OID, so it follows the rename.
--
-- ORDER MATTERS. The client schema (`schema.dart`), the Dart model and the
-- sync-stream queries all read the NEW names:
--   1. apply this migration;
--   2. then Validate → Deploy the updated `powersync/sync-streams.yaml`
--      (its queries now read `dim_exercise_note`);
--   3. then ship a build carrying the rename.
-- Between (1) and (2) the still-deployed stream queries `dim_lesson`, which
-- no longer exists, so note sync is down — the window is one dashboard
-- deploy wide. Do not apply (1) on a device that still holds unsynced note
-- writes: its queued `dim_lesson` rows can never upload after this (the
-- client's crud purge drops them, see `database.dart`).
alter table public.dim_lesson rename to dim_exercise_note;

alter table public.dim_exercise_note
  rename column lesson_id to exercise_note_id;
alter table public.dim_exercise_note
  rename column lesson_text to note_text;
alter table public.dim_exercise_note
  rename column lesson_created_date to note_created_date;

-- Policy names are identifiers too. The predicates themselves follow the
-- column renames on their own (Postgres stores attribute numbers, not names).
-- IF EXISTS keeps this file re-runnable against a history where a policy was
-- renamed by hand.
alter policy if exists "dim_lesson owner access"
  on public.dim_exercise_note
  rename to "dim_exercise_note owner access";
alter policy if exists "dim_lesson friend access"
  on public.dim_exercise_note
  rename to "dim_exercise_note friend access";
alter policy if exists "dim_lesson coach access"
  on public.dim_exercise_note
  rename to "dim_exercise_note coach access";
