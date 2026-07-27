-- Minimum/latest app version per platform, used to gate app launch behind a
-- forced or recommended update. Must be readable by anonymous users, since
-- the version check runs before login.
create table if not exists public.app_config (
  platform text primary key check (platform in ('ios', 'android')),
  min_version text not null,
  latest_version text not null,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

create policy "app_config is publicly readable"
  on public.app_config
  for select
  to anon, authenticated
  using (true);

grant select on public.app_config to anon, authenticated;

insert into public.app_config (platform, min_version, latest_version)
values
  ('ios', '1.0.0', '1.0.0'),
  ('android', '1.0.0', '1.0.0')
on conflict (platform) do nothing;
