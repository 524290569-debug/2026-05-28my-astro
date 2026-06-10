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
  created_at timestamp without time zone not null default (now() at time zone 'Asia/Shanghai')
);

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'megastructure_visits'
      and column_name = 'created_at'
      and data_type = 'timestamp with time zone'
  ) then
    alter table public.megastructure_visits
      alter column created_at type timestamp without time zone
        using created_at at time zone 'Asia/Shanghai';
  end if;

  alter table public.megastructure_visits
    alter column created_at set default (now() at time zone 'Asia/Shanghai');
end $$;

comment on table public.megastructure_visits is '巨构主义页面访问记录表，记录页面访问、登录、场景切换以及浏览器可提供的设备环境信息。';
comment on column public.megastructure_visits.id is '访问记录 ID。';
comment on column public.megastructure_visits.event_type is '访问事件类型，view 为浏览或切换场景，login 为登录成功。';
comment on column public.megastructure_visits.page is '访问页面标识，当前固定为 megastructure。';
comment on column public.megastructure_visits.scene is '访问发生时所在的背景场景 ID。';
comment on column public.megastructure_visits.session_id is '浏览器本地生成的访问会话 ID，用于粗略区分同一浏览器的连续访问。';
comment on column public.megastructure_visits.user_id is '登录用户 ID，未登录访问为空，关联 comment_profiles.id。';
comment on column public.megastructure_visits.display_name is '访问时的用户显示名称，未登录访问为空。';
comment on column public.megastructure_visits.email is '访问时的用户邮箱，未登录访问为空。';
comment on column public.megastructure_visits.path is '访问时的页面路径。';
comment on column public.megastructure_visits.referrer is '浏览器提供的来源页面地址，可能为空。';
comment on column public.megastructure_visits.user_agent is '浏览器 User-Agent 字符串，用于粗略识别浏览器和系统。';
comment on column public.megastructure_visits.language is '浏览器首选语言。';
comment on column public.megastructure_visits.timezone is '浏览器时区名称。';
comment on column public.megastructure_visits.viewport_width is '浏览器视口宽度，单位像素。';
comment on column public.megastructure_visits.viewport_height is '浏览器视口高度，单位像素。';
comment on column public.megastructure_visits.screen_width is '设备屏幕宽度，单位像素。';
comment on column public.megastructure_visits.screen_height is '设备屏幕高度，单位像素。';
comment on column public.megastructure_visits.device_pixel_ratio is '设备像素比。';
comment on column public.megastructure_visits.hardware_concurrency is '浏览器暴露的逻辑处理器数量，属于近似设备信息。';
comment on column public.megastructure_visits.device_memory is '浏览器暴露的设备内存估算值，单位 GB，可能为空。';
comment on column public.megastructure_visits.platform is '浏览器提供的平台标识，可能不完全可靠。';
comment on column public.megastructure_visits.connection_type is '浏览器网络连接类型，可能为空。';
comment on column public.megastructure_visits.effective_type is '浏览器估算的有效网络类型，例如 4g、3g，可能为空。';
comment on column public.megastructure_visits.downlink is '浏览器估算的下行带宽，单位 Mbps，可能为空。';
comment on column public.megastructure_visits.reduced_motion is '访问者是否启用了减少动态效果偏好。';
comment on column public.megastructure_visits.color_scheme is '访问者系统颜色模式偏好，dark 或 light。';
comment on column public.megastructure_visits.touch_points is '设备支持的最大触控点数量。';
comment on column public.megastructure_visits.created_at is '访问记录发生时间，由前端按浏览器本地时间写入，不做时区转换。';

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
