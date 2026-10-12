-- 2026-08-26: is_archived (bool) -> date_archived (timestamptz) on the four
-- top-level dims: exercises, variations, planned sessions, programs.
-- NULL = active; a timestamp = archived (and sortable, latest first).
-- Their child tables (dim_planned_session_exercise/_set) and dim_lesson keep
-- the boolean — their archive state is an internal lifecycle detail, never
-- shown to the user.

alter table public.dim_exercise add column date_archived timestamptz;
update public.dim_exercise set date_archived = now() where is_archived;
alter table public.dim_exercise drop column is_archived;

alter table public.dim_variation add column date_archived timestamptz;
update public.dim_variation set date_archived = now() where is_archived;
alter table public.dim_variation drop column is_archived;

alter table public.dim_planned_session add column date_archived timestamptz;
update public.dim_planned_session set date_archived = now() where is_archived;
alter table public.dim_planned_session drop column is_archived;

alter table public.dim_program add column date_archived timestamptz;
update public.dim_program set date_archived = now() where is_archived;
alter table public.dim_program drop column is_archived;
