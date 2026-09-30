-- الجزء 1 من 4 — شغّل الأجزاء بالترتيب
-- =====================================================================
--  المبرمج المجهول — Supabase schema
--  شغّل هذا الملف كاملًا مرة واحدة من: Supabase → SQL Editor → New query
--  (آمن لإعادة التشغيل: يستخدم IF NOT EXISTS / OR REPLACE قدر الإمكان)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1) الجداول
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique
    check (username ~ '^[a-z0-9_.]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 50),
  bio text default '' check (char_length(bio) <= 300),
  avatar_url text,
  is_admin boolean not null default false,
  is_banned boolean not null default false,
  notifications_enabled boolean not null default true,
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  app_enabled boolean not null default true,
  maintenance_message text not null default 'التطبيق متوقف مؤقتًا للصيانة، يرجى المحاولة لاحقًا.',
  updated_at timestamptz not null default now()
);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct','group')),
  name text check (name is null or char_length(name) between 1 and 60),
  description text default '',
  avatar_url text,
  is_public boolean not null default false,
  direct_key text unique,
  created_by uuid references public.profiles(id) on delete set null,
  last_message_at timestamptz not null default now(),
  last_message_preview text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  muted boolean not null default false,
  archived boolean not null default false,
  last_read_at timestamptz not null default 'epoch',
  last_delivered_at timestamptz not null default 'epoch',
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists idx_members_user on public.conversation_members(user_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  client_id text unique,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  type text not null default 'text'
    check (type in ('text','image','video','file','audio','system')),
  content text check (content is null or char_length(content) <= 4000),
  media_path text,
  file_name text,
  file_size bigint,
  reply_to uuid references public.messages(id) on delete set null,
  forwarded boolean not null default false,
  pinned boolean not null default false,
  deleted boolean not null default false,
  edited_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_messages_conv_created on public.messages(conversation_id, created_at desc);
create index if not exists idx_messages_sender_created on public.messages(sender_id, created_at desc);

create table if not exists public.contact_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (sender_id <> receiver_id)
);
create unique index if not exists uq_contact_pair
  on public.contact_requests (least(sender_id, receiver_id), greatest(sender_id, receiver_id));

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete set null,
  reported_user_id uuid references public.profiles(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid references public.conversations(id) on delete set null,
  reason text not null check (char_length(reason) between 2 and 500),
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text default '',
  data jsonb not null default '{}'::jsonb,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_notifications_user on public.notifications(user_id, created_at desc);

-- ---------------------------------------------------------------------
-- 2) دوال مساعدة
-- ---------------------------------------------------------------------

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

create or replace function public.is_banned() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_banned from profiles where id = auth.uid()), false);
$$;

create or replace function public.is_member(conv uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from conversation_members
                where conversation_id = conv and user_id = auth.uid());
$$;

create or replace function public.member_role(conv uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from conversation_members
  where conversation_id = conv and user_id = auth.uid();
$$;

create or replace function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

create or replace function public.can_send(conv uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  t text;
  other uuid;
begin
  if not is_member(conv) or is_banned() then return false; end if;
  if not (select app_enabled from app_settings where id = 1) and not is_admin() then
    return false;
  end if;
  select type into t from conversations where id = conv;
  if t = 'direct' then
    select user_id into other from conversation_members
      where conversation_id = conv and user_id <> auth.uid() limit 1;
    if other is not null and is_blocked_between(auth.uid(), other) then
      return false;
    end if;
  end if;
  return true;
end $$;

create or replace function public.username_available(uname text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists(select 1 from profiles where username = lower(uname));
$$;

create or replace function public.notify_user(uid uuid, ntype text, ntitle text, nbody text, ndata jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from profiles where id = uid and notifications_enabled) then
    insert into notifications(user_id, type, title, body, data)
    values (uid, ntype, ntitle, coalesce(nbody, ''), coalesce(ndata, '{}'::jsonb));
  end if;
end $$;
revoke execute on function public.notify_user(uuid, text, text, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) Triggers
-- ---------------------------------------------------------------------

-- إنشاء ملف شخصي تلقائيًا عند التسجيل
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uname text := lower(coalesce(new.raw_user_meta_data->>'username', ''));
begin
  if uname !~ '^[a-z0-9_.]{3,24}$' or exists(select 1 from profiles where username = uname) then
    uname := 'user_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  insert into profiles(id, username, display_name)
  values (new.id, uname,
          coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), uname));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- حماية الأعمدة الحساسة في profiles من التعديل من قبل المستخدم
create or replace function public.protect_profile_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() فارغ عند التشغيل من SQL Editor (المالك) — مسموح
  if auth.uid() is not null and not is_admin() then
    new.is_admin := old.is_admin;
    new.is_banned := old.is_banned;
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  new.username := lower(new.username);
  return new;
end $$;
drop trigger if exists trg_protect_profile on public.profiles;
create trigger trg_protect_profile before update on public.profiles
  for each row execute function public.protect_profile_columns();

-- Rate limiting + تحديث المحادثة + إشعارات الإشارة (@username)
create or replace function public.before_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type <> 'system' then
    if (select count(*) from messages
        where sender_id = new.sender_id and created_at > now() - interval '10 seconds') >= 20 then
      raise exception 'rate_limited: أرسلت رسائل كثيرة بسرعة، انتظر قليلًا';
    end if;
  end if;
  new.created_at := now();
  new.pinned := false;
  new.deleted := false;
  new.edited_at := null;
  return new;
end $$;
drop trigger if exists trg_before_message on public.messages;
create trigger trg_before_message before insert on public.messages
  for each row execute function public.before_message_insert();

create or replace function public.after_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  preview text;
  sender_name text;
  conv_name text;
  conv_type text;
  mention text;
  mentioned uuid;
begin
  preview := case new.type
    when 'image' then '📷 صورة'
    when 'video' then '🎬 فيديو'
    when 'audio' then '🎤 رسالة صوتية'
    when 'file'  then '📎 ' || coalesce(new.file_name, 'ملف')
    else left(coalesce(new.content, ''), 120) end;

  update conversations set last_message_at = new.created_at, last_message_preview = preview
  where id = new.conversation_id;

  -- المرسل قرأ رسالته
  update conversation_members set last_read_at = new.created_at, last_delivered_at = new.created_at,
         archived = false
  where conversation_id = new.conversation_id and user_id = new.sender_id;

  -- إشعارات الإشارة @username
  if new.type = 'text' and new.content like '%@%' then
    select display_name into sender_name from profiles where id = new.sender_id;
    select name, type into conv_name, conv_type from conversations where id = new.conversation_id;
    for mention in
      select distinct lower(m[1]) from regexp_matches(new.content, '@([A-Za-z0-9_.]{3,24})', 'g') as m
    loop
      select p.id into mentioned from profiles p
        join conversation_members cm on cm.user_id = p.id and cm.conversation_id = new.conversation_id
        where p.username = mention and p.id <> new.sender_id;
      if mentioned is not null then
        perform notify_user(mentioned, 'mention',
          coalesce(sender_name, 'مستخدم') || ' أشار إليك',
          left(new.content, 120),
          jsonb_build_object('conversation_id', new.conversation_id));
      end if;
      mentioned := null;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists trg_after_message on public.messages;
create trigger trg_after_message after insert on public.messages
  for each row execute function public.after_message_insert();

-- إشعار طلب تواصل
create or replace function public.after_contact_request() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if tg_op = 'INSERT' then
    select display_name into n from profiles where id = new.sender_id;
    perform notify_user(new.receiver_id, 'contact_request', 'طلب تواصل جديد',
      coalesce(n, '') || ' أرسل لك طلب تواصل', jsonb_build_object('user_id', new.sender_id));
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status <> 'accepted' then
    select display_name into n from profiles where id = new.receiver_id;
    perform notify_user(new.sender_id, 'contact_accepted', 'تم قبول طلبك',
      coalesce(n, '') || ' قبل طلب التواصل', jsonb_build_object('user_id', new.receiver_id));
  end if;
  return new;
end $$;
drop trigger if exists trg_contact_request on public.contact_requests;
create trigger trg_contact_request after insert or update on public.contact_requests
  for each row execute function public.after_contact_request();
