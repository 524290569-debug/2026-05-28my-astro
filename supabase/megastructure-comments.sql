create extension if not exists pgcrypto;

create table if not exists public.comment_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.megastructure_comments (
  id uuid primary key default gen_random_uuid(),
  page text not null default 'megastructure',
  user_id uuid not null references public.comment_profiles(id) on delete cascade,
  x numeric(6,2) not null check (x >= 0 and x <= 100),
  y numeric(6,2) not null check (y >= 0 and y <= 100),
  body text not null check (char_length(body) between 1 and 180),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

alter table public.comment_profiles enable row level security;
alter table public.megastructure_comments enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.comment_profiles to anon, authenticated;
grant select on public.megastructure_comments to anon, authenticated;
grant insert, update, delete on public.megastructure_comments to authenticated;

create or replace function public.handle_new_comment_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.comment_profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update
  set display_name = excluded.display_name;

  return new;
end;
$$;

drop trigger if exists on_auth_comment_user_created on auth.users;

create trigger on_auth_comment_user_created
after insert on auth.users
for each row execute function public.handle_new_comment_user();

create or replace function public.is_comment_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.comment_profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

drop policy if exists "profiles readable" on public.comment_profiles;
create policy "profiles readable"
on public.comment_profiles for select
using (true);

drop policy if exists "read approved own or admin comments" on public.megastructure_comments;
create policy "read approved own or admin comments"
on public.megastructure_comments for select
using (
  status = 'approved'
  or user_id = auth.uid()
  or public.is_comment_admin()
);

drop policy if exists "authenticated users insert own pending comments" on public.megastructure_comments;
create policy "authenticated users insert own pending comments"
on public.megastructure_comments for insert
to authenticated
with check (
  user_id = auth.uid()
  and status = 'pending'
);

drop policy if exists "owners delete own comments" on public.megastructure_comments;
create policy "owners delete own comments"
on public.megastructure_comments for delete
to authenticated
using (user_id = auth.uid());

drop policy if exists "admins update comments" on public.megastructure_comments;
create policy "admins update comments"
on public.megastructure_comments for update
to authenticated
using (public.is_comment_admin())
with check (public.is_comment_admin());

drop policy if exists "admins delete comments" on public.megastructure_comments;
create policy "admins delete comments"
on public.megastructure_comments for delete
to authenticated
using (public.is_comment_admin());

-- After registering your admin email on the page, run this with your real email:
-- update public.comment_profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'your-email@example.com');
