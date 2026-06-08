create extension if not exists pgcrypto;

create table if not exists public.comment_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null check (char_length(display_name) between 1 and 24),
  role text not null default 'user' check (role in ('user', 'admin')),
  failed_login_count integer not null default 0 check (failed_login_count >= 0),
  is_locked boolean not null default false,
  locked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.comment_profiles
  add column if not exists email text,
  add column if not exists failed_login_count integer not null default 0 check (failed_login_count >= 0),
  add column if not exists is_locked boolean not null default false,
  add column if not exists locked_at timestamptz;

update public.comment_profiles profile
set email = lower(auth_user.email)
from auth.users auth_user
where profile.id = auth_user.id
  and (profile.email is null or profile.email <> lower(auth_user.email));

create unique index if not exists comment_profiles_email_unique
on public.comment_profiles (lower(email))
where email is not null;

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
  insert into public.comment_profiles (id, email, display_name)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update
  set
    display_name = excluded.display_name,
    email = lower(new.email);

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

create or replace function public.is_comment_account_locked(p_user_id uuid default auth.uid())
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((
    select is_locked from public.comment_profiles
    where id = p_user_id
  ), false);
$$;

create or replace function public.comment_email_registered(p_email text)
returns boolean
language sql
security definer
set search_path = public, auth
stable
as $$
  select exists (
    select 1 from auth.users
    where lower(email) = lower(trim(p_email))
  );
$$;

create or replace function public.comment_login_lock_status(p_email text)
returns table(email_registered boolean, is_locked boolean, failed_count integer)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_user_id uuid;
begin
  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user_id is null then
    return query select false, false, 0;
    return;
  end if;

  insert into public.comment_profiles (id, email, display_name)
  select id, lower(email), coalesce(raw_user_meta_data->>'display_name', split_part(email, '@', 1))
  from auth.users
  where id = target_user_id
  on conflict (id) do nothing;

  return query
  select
    true,
    coalesce(profile.is_locked, false),
    coalesce(profile.failed_login_count, 0)
  from public.comment_profiles profile
  where profile.id = target_user_id;
end;
$$;

create or replace function public.register_comment_login_failure(p_email text)
returns table(email_registered boolean, is_locked boolean, failed_count integer)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_user_id uuid;
  next_count integer;
begin
  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user_id is null then
    return query select false, false, 0;
    return;
  end if;

  insert into public.comment_profiles (id, email, display_name)
  select id, lower(email), coalesce(raw_user_meta_data->>'display_name', split_part(email, '@', 1))
  from auth.users
  where id = target_user_id
  on conflict (id) do nothing;

  update public.comment_profiles
  set
    failed_login_count = case when is_locked then failed_login_count else failed_login_count + 1 end,
    is_locked = is_locked or failed_login_count + 1 >= 3,
    locked_at = case
      when is_locked or failed_login_count + 1 < 3 then locked_at
      else now()
    end
  where id = target_user_id
  returning failed_login_count into next_count;

  return query
  select
    true,
    coalesce(profile.is_locked, false),
    coalesce(profile.failed_login_count, next_count)
  from public.comment_profiles profile
  where profile.id = target_user_id;
end;
$$;

create or replace function public.clear_comment_login_failures()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.comment_profiles
  set failed_login_count = 0
  where id = auth.uid()
    and is_locked = false;
end;
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
  and not public.is_comment_account_locked(auth.uid())
);

drop policy if exists "owners delete own comments" on public.megastructure_comments;
create policy "owners delete own comments"
on public.megastructure_comments for delete
to authenticated
using (
  user_id = auth.uid()
  and not public.is_comment_account_locked(auth.uid())
);

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

grant execute on function public.is_comment_account_locked(uuid) to anon, authenticated;
grant execute on function public.comment_email_registered(text) to anon, authenticated;
grant execute on function public.comment_login_lock_status(text) to anon, authenticated;
grant execute on function public.register_comment_login_failure(text) to anon, authenticated;
grant execute on function public.clear_comment_login_failures() to authenticated;

-- After registering your admin email on the page, run this with your real email:
-- update public.comment_profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'your-email@example.com');

-- To unlock an account manually:
-- update public.comment_profiles
-- set is_locked = false, failed_login_count = 0, locked_at = null
-- where email = 'locked-email@example.com';
