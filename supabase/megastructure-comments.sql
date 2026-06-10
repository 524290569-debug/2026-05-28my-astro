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
  reviewed_at timestamptz,
  review_reason text,
  review_score numeric(5,2) not null default 0,
  review_labels jsonb not null default '[]'::jsonb,
  reviewed_by text
);

alter table public.megastructure_comments
  add column if not exists review_reason text,
  add column if not exists review_score numeric(5,2) not null default 0,
  add column if not exists review_labels jsonb not null default '[]'::jsonb,
  add column if not exists reviewed_by text;

comment on table public.comment_profiles is '巨构主义评论用户资料表，补充 Supabase Auth 用户的展示名称、角色和登录锁定状态。';
comment on column public.comment_profiles.id is '用户 ID，关联 auth.users.id。';
comment on column public.comment_profiles.email is '用户登录邮箱，统一按小写保存，用于注册校验和管理员识别。';
comment on column public.comment_profiles.display_name is '页面显示名称，注册时填写，评论列表中展示。';
comment on column public.comment_profiles.role is '用户角色，user 为普通用户，admin 为评论管理员。';
comment on column public.comment_profiles.failed_login_count is '连续密码错误次数，达到锁定阈值后账号会被锁定。';
comment on column public.comment_profiles.is_locked is '账号是否已被锁定，锁定后不能继续提交或删除普通评论。';
comment on column public.comment_profiles.locked_at is '账号被锁定的时间。';
comment on column public.comment_profiles.created_at is '用户资料记录创建时间。';

comment on table public.megastructure_comments is '巨构主义页面评论表，记录评论内容、所在场景页面、坐标位置和审核状态。';
comment on column public.megastructure_comments.id is '评论 ID。';
comment on column public.megastructure_comments.page is '评论所属页面或场景，megastructure 为旧数据，megastructure:场景ID 为按背景分开的新数据。';
comment on column public.megastructure_comments.user_id is '评论作者用户 ID，关联 comment_profiles.id。';
comment on column public.megastructure_comments.x is '评论标记在画面中的横向百分比位置，范围 0 到 100。';
comment on column public.megastructure_comments.y is '评论标记在画面中的纵向百分比位置，范围 0 到 100。';
comment on column public.megastructure_comments.body is '评论正文，长度限制 1 到 180 个字符。';
comment on column public.megastructure_comments.status is '评论审核状态，pending 待审核，approved 已通过，rejected 已拒绝。';
comment on column public.megastructure_comments.created_at is '评论提交时间。';
comment on column public.megastructure_comments.reviewed_at is '评论被审核的时间。';
comment on column public.megastructure_comments.review_reason is '规则或人工审核给出的中文说明。';
comment on column public.megastructure_comments.review_score is '规则审核风险分，0 表示低风险，1 表示高风险。';
comment on column public.megastructure_comments.review_labels is '规则审核命中的标签列表，JSON 数组。';
comment on column public.megastructure_comments.reviewed_by is '审核来源，auto_rule_v1 表示数据库规则自动审核，admin 表示管理员人工处理。';

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

create or replace function public.apply_megastructure_comment_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_body text;
  body_length integer;
  link_count integer := 0;
  labels jsonb := '[]'::jsonb;
  target_status text := 'approved';
  target_reason text := '规则审核通过。';
  target_score numeric(5,2) := 0.05;
begin
  normalized_body := lower(trim(coalesce(new.body, '')));
  body_length := char_length(normalized_body);

  select count(*) into link_count
  from regexp_matches(
    normalized_body,
    '(https?://|www\.|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|[a-z0-9.-]+\.(com|cn|net|org|top|xyz|vip))',
    'g'
  ) as match;

  if body_length < 2 then
    target_status := 'pending';
    target_reason := '内容过短，需要人工确认。';
    target_score := 0.45;
    labels := labels || jsonb_build_array('too_short');
  elsif normalized_body ~ '(博彩|赌博|彩票|贷款|代刷|刷单|裸聊|约炮|色情|成人|发票|加微信|加qq|vx[[:space:]:：]*[a-z0-9_-]{3,}|qq[[:space:]:：]*[0-9]{5,})' then
    target_status := 'rejected';
    target_reason := '命中广告、交易或成人内容规则。';
    target_score := 0.95;
    labels := labels || jsonb_build_array('spam_or_adult');
  elsif normalized_body ~ '(傻[逼比]|煞笔|脑残|废物|垃圾|去死|妈的|操你|草你|死全家)' then
    target_status := 'rejected';
    target_reason := '命中辱骂或攻击性用词规则。';
    target_score := 0.9;
    labels := labels || jsonb_build_array('abuse');
  elsif link_count >= 2 then
    target_status := 'rejected';
    target_reason := '包含多个链接或外部地址。';
    target_score := 0.85;
    labels := labels || jsonb_build_array('multi_link');
  elsif link_count = 1 or normalized_body ~ '(微信|qq|联系方式|联系我|私聊|群号|公众号|1[3-9][0-9]{9})' then
    target_status := 'pending';
    target_reason := '包含链接或联系方式，需要人工审核。';
    target_score := 0.65;
    labels := labels || jsonb_build_array('contact_or_link');
  elsif normalized_body ~ '[!！?？。,.，、~～]{8,}' then
    target_status := 'pending';
    target_reason := '包含大量连续标点，需要人工确认。';
    target_score := 0.4;
    labels := labels || jsonb_build_array('punctuation_spam');
  end if;

  new.status := target_status;
  new.review_reason := target_reason;
  new.review_score := target_score;
  new.review_labels := labels;
  new.reviewed_by := 'auto_rule_v1';

  if target_status = 'pending' then
    new.reviewed_at := null;
  else
    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists megastructure_comments_auto_review on public.megastructure_comments;

create trigger megastructure_comments_auto_review
before insert or update of body on public.megastructure_comments
for each row execute function public.apply_megastructure_comment_review();

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
drop policy if exists "authenticated users insert own comments" on public.megastructure_comments;
create policy "authenticated users insert own comments"
on public.megastructure_comments for insert
to authenticated
with check (
  user_id = auth.uid()
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
