-- Give fact_workout_set its own user_id, backfilled from its parent workout.
-- Every other table in the app is user-scoped; this makes workout sets
-- user-scoped too, which simplifies the sync config (one user-scoped stream
-- instead of a per-workout bucket) and enables coaching queries that select
-- an athlete's sets directly.
alter table public.fact_workout_set add column user_id uuid;

update public.fact_workout_set s
set user_id = w.user_id
from public.fact_workout w
where w.user_workout_id = s.user_workout_id;

alter table public.fact_workout_set alter column user_id set not null;
alter table public.fact_workout_set
  add constraint fact_workout_set_user_id_fkey
  foreign key (user_id) references public.dim_user (user_id);
