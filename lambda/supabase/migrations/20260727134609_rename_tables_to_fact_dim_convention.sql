-- Drop dead legacy catalog tables (superseded by user_custom_exercise/
-- user_custom_variation, zero references anywhere in app code or DB).
drop table if exists public.dim_exercise;
drop table if exists public.dim_exercise_variation;

-- Rename to converge every table on the fact_/dim_ convention, and drop the
-- redundant "user" word (each table is already user-scoped via its own
-- user_id column).
alter table public.user_custom_exercise                rename to dim_exercise;
alter table public.user_custom_variation                rename to dim_variation;
alter table public.user_custom_exercise_variation_bridge rename to dim_exercise_variation_bridge;
alter table public.fact_user_weight                     rename to fact_bodyweight;
alter table public.fact_user_workout                     rename to fact_workout;
alter table public.user_program                          rename to dim_program;
alter table public.user_program_run                      rename to fact_program_run;
alter table public.program_planned_workout               rename to dim_planned_workout;
alter table public.program_planned_set                   rename to dim_planned_set;
