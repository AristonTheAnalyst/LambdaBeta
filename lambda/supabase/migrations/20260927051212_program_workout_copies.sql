-- 2026-09-27: copy-on-add — a workout in a program is a COPY, never a link.
--
-- THE RULE: the Workouts library is a SOURCE, not a shared dependency. Importing
-- a workout into a program makes a private copy. Editing the copy never touches
-- the library original; the original stays listed in the library exactly as it
-- was. `base_session_id` records where a copy came from so the program can push
-- improvements back on request — copies never TRACK the base, so nothing warns
-- when the two drift.
--
--   base_session_id IS NULL  → this workout originated here: a library workout,
--                              or one authored inside a program.
--   base_session_id IS SET   → this is a program copy of the workout it names.
--
-- WHY A PLAIN REF, NO FOREIGN KEY: "create a workout offline, then import it"
-- must not be able to fail an FK on upload. Rows upload in whatever order the
-- queue happens to hold them, and a copy can legitimately reach the server
-- before the original it names. Same reasoning as
-- fact_session_exercise_set.planned_set_id.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE ONE DATA TRANSFORMATION IN THIS MIGRATION
--
-- Every existing dim_planned_session_program row points at a SHARED template.
-- Under copy-on-add that is invalid state, so each linked template is
-- deep-copied into a program-local copy and the join row is repointed at the
-- copy. The originals lose their join row and return to being library workouts
-- — which is exactly what they now are.
--
-- The copies keep their source's name, notes, created_date and DATE_ARCHIVED
-- verbatim: this is a change of identity, not of content, so the programs must
-- look byte-identical afterwards. An archived program's workouts stay archived.
--
-- The join rows are UPDATEd rather than deleted-and-reinserted so PowerSync
-- sees an UPDATE op. A delete + insert of the same primary key can reach the
-- server out of order, and the row would be transiently absent.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Lineage ─────────────────────────────────────────────────────────────
alter table public.dim_planned_session add column base_session_id text;

comment on column public.dim_planned_session.base_session_id is
  'Copy-on-add provenance. NULL = originated here (library workout, or authored '
  'in a program). Set = the library workout this is a program-local copy of. '
  'Plain ref, no FK: an offline create-then-import must not fail on upload.';

-- ── 2. The unique pair is now wrong ────────────────────────────────────────
-- UNIQUE (program_id, planned_session_id) enforced "a template appears once per
-- program". Under copy-on-add each program holds its OWN copies, so the pair
-- would forbid a program from holding two copies of the same original — which
-- is a perfectly ordinary thing to want (the same workout twice a week).
alter table public.dim_planned_session_program
  drop constraint dim_planned_session_program_program_id_planned_session_id_key;

-- ── 3. Detach: every linked template becomes a program-local copy ──────────
-- One statement, so it is atomic: no temp tables (whose lifetime depends on
-- how the runner wraps a migration) and no partial state. All the CTEs below
-- read the same snapshot, taken before anything is written — which is what
-- lets the final UPDATE match the ORIGINAL join rows while the new copies
-- exist in the same statement.
with copy_map as (
  select s.session_id             as old_id,
         gen_random_uuid()::text  as new_id
  from public.dim_planned_session s
  where exists (
    select 1 from public.dim_planned_session_program l
    where l.planned_session_id = s.session_id
  )
),
exercise_map as (
  select e.planned_exercise_id    as old_id,
         gen_random_uuid()::text  as new_id,
         m.new_id                 as new_session_id
  from public.dim_planned_session_exercise e
  join copy_map m on m.old_id = e.planned_session_id
),
insert_session as (
  insert into public.dim_planned_session
    (session_id, user_id, name, notes, created_date, date_archived,
     base_session_id)
  select m.new_id,
         s.user_id,
         s.name,
         s.notes,
         s.created_date,
         s.date_archived,
         -- coalesce, not s.session_id: a chain of copies still points home.
         coalesce(s.base_session_id, s.session_id)
  from public.dim_planned_session s
  join copy_map m on m.old_id = s.session_id
  returning 1
),
insert_exercise as (
  insert into public.dim_planned_session_exercise
    (planned_exercise_id, user_id, planned_session_id, custom_exercise_id,
     exercise_order, is_archived)
  select x.new_id,
         e.user_id,
         x.new_session_id,
         e.custom_exercise_id,
         e.exercise_order,
         -- Faithful, archived stubs included: the copy must render identically.
         e.is_archived
  from public.dim_planned_session_exercise e
  join exercise_map x on x.old_id = e.planned_exercise_id
  returning 1
),
insert_set as (
  insert into public.dim_planned_session_exercise_set
    (planned_set_id, user_id, planned_exercise_id, custom_variation_id,
     set_number, target_weight, target_reps, target_notes, is_archived)
  select gen_random_uuid()::text,
         t.user_id,
         x.new_id,
         t.custom_variation_id,
         t.set_number,
         t.target_weight,
         t.target_reps,
         t.target_notes,
         t.is_archived
  from public.dim_planned_session_exercise_set t
  join exercise_map x on x.old_id = t.planned_exercise_id
  returning 1
),
repoint_link as (
  update public.dim_planned_session_program l
  set planned_session_id = m.new_id
  from copy_map m
  where l.planned_session_id = m.old_id
  returning 1
),
touch_program as (
  -- A workout changing identity IS a structural change to the program, so its
  -- updated_date moves. (touchProgram() does the same thing from the app.)
  --
  -- Matches on the OLD ids: every CTE here reads the same snapshot, taken
  -- before the statement ran, so the join rows still hold the pre-copy ids.
  -- Matching on copy_map.new_id would match nothing at all.
  update public.dim_program p
  set program_updated_date = now()
  where exists (
    select 1
    from public.dim_planned_session_program l
    join copy_map m on m.old_id = l.planned_session_id
    where l.program_id = p.program_id
  )
  returning 1
)
select
  (select count(*) from copy_map)       as copies,
  (select count(*) from insert_session) as sessions_inserted,
  (select count(*) from insert_exercise) as exercises_inserted,
  (select count(*) from insert_set)     as sets_inserted,
  (select count(*) from repoint_link)   as links_repointed,
  (select count(*) from touch_program)  as programs_touched;

-- NO PUBLICATION OR GRANT CHANGES: dim_planned_session is already in the
-- powersync publication, and `add table` covers every column — including this
-- new one. The client schema (lib/core/powersync/schema.dart) declares it, and
-- every sync stream is `SELECT *`, so the column flows down with no dashboard
-- step. If it ever fails to appear after syncing, redeploying the streams
-- forces PowerSync to reprocess the table.
