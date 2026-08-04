-- Snapshot exercise/variation names onto set rows so later renames/edits to
-- the exercise library never rewrite historical sets. History reads use these
-- columns (COALESCE back to the dictionary for pre-migration gaps).

alter table public.fact_workout_set
  add column exercise_name text,
  add column variation_name text;

alter table public.dim_planned_set
  add column exercise_name text,
  add column variation_name text;

-- Backfill existing rows from the current dictionaries.
update public.fact_workout_set s set exercise_name = e.exercise_name
  from public.dim_exercise e where e.custom_exercise_id = s.custom_exercise_id;
update public.fact_workout_set s set variation_name = v.variation_name
  from public.dim_variation v where v.custom_variation_id = s.custom_variation_id;
update public.dim_planned_set s set exercise_name = e.exercise_name
  from public.dim_exercise e where e.custom_exercise_id = s.custom_exercise_id;
update public.dim_planned_set s set variation_name = v.variation_name
  from public.dim_variation v where v.custom_variation_id = s.custom_variation_id;
