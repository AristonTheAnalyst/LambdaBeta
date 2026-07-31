-- PR redesign: absolute is no longer a PR concept; weight-class renamed to
-- weight-max. Absolute rows are deleted (they aren't meaningful as an
-- achievement axis), and legacy 'weightClass' pr_type values are renamed so
-- the new enum maps cleanly.
delete from public.fact_pr where pr_type = 'absolute';

update public.fact_pr set pr_type = 'weightMax' where pr_type = 'weightClass';
