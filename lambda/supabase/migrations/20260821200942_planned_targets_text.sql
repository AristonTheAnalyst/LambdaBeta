-- Planned targets become free text so planners can record ranges
-- ("8-15" reps, "60-70" kg) — a planned value is a hint, not a literal.
-- The client schema already stores both columns as text; this aligns
-- Postgres with that. Sync streams use SELECT * and need redeploying
-- after this lands (PowerSync Dashboard → Validate → Deploy).

alter table public.dim_planned_session_set
  alter column target_reps type text using
    case when target_reps is null or cardinality(target_reps) = 0 then null
         else array_to_string(target_reps, ',') end;

alter table public.dim_planned_session_set
  alter column target_weight type text using
    case when target_weight is null then null
         else regexp_replace(target_weight::text, '(\.0+)$', '') end;
