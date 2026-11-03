-- Stamp the author of every coach-written row, server-side (2026-10-28)
--
-- Phase 0 added `created_by_user_id` and the coach INSERT policies, which
-- demand `created_by_user_id = auth.uid()`. Making every client write send it
-- would mean threading an author through a dozen repository funnels and
-- trusting each one; a BEFORE INSERT trigger is one place, authoritative, and
-- impossible to forget. It also gives the column one meaning:
--
--   NULL                    -> the owner wrote the row
--   a user id (never the owner) -> that user wrote it on the owner's behalf
--
-- The RLS WITH CHECK expressions are evaluated AFTER BEFORE triggers, so the
-- coach policy sees the stamped value and passes; the owner's own INSERT
-- leaves it NULL. (Client rows carry NULL locally until the server copy syncs
-- back — the author is provenance, not a local permission.)
create or replace function public.stamp_row_author()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from auth.uid() then
    -- Someone acting on another user's row: the author is the caller.
    new.created_by_user_id := auth.uid()::text;
  else
    -- The owner's own row: authorship is the owner, so the column stays
    -- NULL and `coalesce(created_by_user_id, user_id)` reads correctly.
    new.created_by_user_id := null;
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'fact_session', 'fact_session_exercise', 'fact_session_exercise_set',
    'dim_exercise', 'dim_variation',
    'dim_planned_session', 'dim_planned_session_exercise',
    'dim_planned_session_exercise_set', 'dim_exercise_note',
    'fact_goal', 'fact_goal_target'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   t || '_stamp_author', t);
    execute format(
      'create trigger %I before insert on public.%I '
      'for each row execute function public.stamp_row_author()',
      t || '_stamp_author', t);
  end loop;
end $$;
