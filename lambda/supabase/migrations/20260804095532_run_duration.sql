-- Per-run duration config, set when a program is begun and editable while
-- running. Sequential programs use target_sessions (how many workouts to log);
-- calendar programs use target_weeks OR an explicit end_date. The program's
-- own length_weeks stays as the program default; these override for progress.

alter table public.fact_program_run
  add column target_sessions integer,
  add column target_weeks integer,
  add column end_date timestamptz;
