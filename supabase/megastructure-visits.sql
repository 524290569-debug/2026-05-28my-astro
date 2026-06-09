create extension if not exists pgcrypto;

create table if not exists public.megastructure_visits (
  id uuid primary key default gen_random_uuid(),
  event_type text not null default 'view' check (event_type in ('view', 'login')),
  page text not null default 'megastructure',
  scene text,
  session_id text not null,
  user_id uuid references public.comment_profiles(id) on delete set null,
  display_name text,
  email text,
  path text,
  referrer text,
  user_agent text,
  language text,
  timezone text,
  viewport_width integer,
  viewport_height integer,
  screen_width integer,
  screen_height integer,
  device_pixel_ratio numeric(5,2),
  hardware_concurrency integer,
  device_memory numeric(5,2),
  platform text,
  connection_type text,
  effective_type text,
  downlink numeric(8,2),
  reduced_motion boolean,
  color_scheme text,
  touch_points integer,
  created_at timestamptz not null default now()
);

alter table public.megastructure_visits enable row level security;

grant usage on schema public to anon, authenticated;
grant insert on public.megastructure_visits to anon, authenticated;
grant select on public.megastructure_visits to authenticated;

create index if not exists megastructure_visits_created_at_idx
on public.megastructure_visits (created_at desc);

create index if not exists megastructure_visits_scene_created_at_idx
on public.megastructure_visits (scene, created_at desc);

create index if not exists megastructure_visits_session_id_idx
on public.megastructure_visits (session_id);

drop policy if exists "visits insertable" on public.megastructure_visits;
create policy "visits insertable"
on public.megastructure_visits for insert
to anon, authenticated
with check (
  user_id is null
  or user_id = auth.uid()
);

drop policy if exists "admins read visits" on public.megastructure_visits;
create policy "admins read visits"
on public.megastructure_visits for select
to authenticated
using (public.is_comment_admin());
