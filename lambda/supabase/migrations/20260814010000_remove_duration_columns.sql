-- =============================================================================
-- Remove duration tracking columns.
--
-- Lambda tracks sets as (exercise, weight, reps). Duration is not a tracking
-- dimension for v1 and is removed everywhere:
--   fact_session_set.duration_seconds          (logged sets)
--   dim_planned_session_set.target_duration_seconds (template sets)
--
-- Rollback:
--   alter table public.fact_session_set
--     add column duration_seconds integer[];
--   alter table public.dim_planned_session_set
--     add column target_duration_seconds integer[];
-- =============================================================================

alter table public.fact_session_set drop column if exists duration_seconds;
alter table public.dim_planned_session_set drop column if exists target_duration_seconds;
