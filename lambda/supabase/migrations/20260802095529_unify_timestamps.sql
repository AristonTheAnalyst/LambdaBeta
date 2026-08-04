-- Unify every date/timestamp column to timestamptz so the whole schema has
-- one timezone-aware type. date -> timestamptz is interpreted as midnight
-- local time and timestamp -> timestamptz as local time, so existing values
-- are preserved without data loss.

alter table public.dim_user
  alter column user_date_created type timestamptz using user_date_created at time zone 'UTC',
  alter column user_date_of_birth type timestamptz using user_date_of_birth at time zone 'UTC';

alter table public.fact_bodyweight
  alter column user_weight_date type timestamptz using user_weight_date at time zone 'UTC',
  alter column created_date type timestamptz using created_date at time zone 'UTC';
