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

-- ---------------------------------------------------------------------
-- 4) RPC — المحادثات والرسائل
-- ---------------------------------------------------------------------

create or replace function public.get_or_create_direct(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  k text;
  cid uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if other = me then raise exception 'لا يمكنك مراسلة نفسك'; end if;
  if is_banned() then raise exception 'حسابك محظور'; end if;
  if is_blocked_between(me, other) then raise exception 'لا يمكن المراسلة: يوجد حظر'; end if;
  k := least(me::text, other::text) || '_' || greatest(me::text, other::text);
  select id into cid from conversations where direct_key = k;
  if cid is null then
    insert into conversations(type, direct_key, created_by) values ('direct', k, me)
      returning id into cid;
    insert into conversation_members(conversation_id, user_id, role)
      values (cid, me, 'member'), (cid, other, 'member');
  end if;
  return cid;
end $$;

create or replace function public.create_group(gname text, gdescription text, gavatar text,
                                               gpublic boolean, member_ids uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cid uuid;
  uid uuid;
  my_name text;
begin
  if me is null or is_banned() then raise exception 'غير مسموح'; end if;
  insert into conversations(type, name, description, avatar_url, is_public, created_by)
    values ('group', gname, coalesce(gdescription, ''), gavatar, coalesce(gpublic, false), me)
    returning id into cid;
  insert into conversation_members(conversation_id, user_id, role) values (cid, me, 'owner');
  select display_name into my_name from profiles where id = me;
  foreach uid in array coalesce(member_ids, '{}') loop
    if uid <> me and not is_blocked_between(me, uid) then
      insert into conversation_members(conversation_id, user_id) values (cid, uid)
        on conflict do nothing;
      perform notify_user(uid, 'group_added', 'تمت إضافتك إلى مجموعة',
        coalesce(my_name, '') || ' أضافك إلى «' || gname || '»',
        jsonb_build_object('conversation_id', cid));
    end if;
  end loop;
  insert into messages(conversation_id, sender_id, type, content)
    values (cid, me, 'system', 'أنشأ ' || coalesce(my_name, '') || ' المجموعة');
  return cid;
end $$;

create or replace function public.update_group(conv uuid, gname text, gdescription text,
                                               gavatar text, gpublic boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if member_role(conv) not in ('owner','admin') then raise exception 'للمشرفين فقط'; end if;
  update conversations set name = coalesce(gname, name),
    description = coalesce(gdescription, description),
    avatar_url = coalesce(gavatar, avatar_url),
    is_public = coalesce(gpublic, is_public)
  where id = conv and type = 'group';
end $$;

create or replace function public.add_group_members(conv uuid, member_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid; gname text; my_name text;
begin
  if member_role(conv) not in ('owner','admin') then raise exception 'للمشرفين فقط'; end if;
  select name into gname from conversations where id = conv;
  select display_name into my_name from profiles where id = auth.uid();
  foreach uid in array member_ids loop
    if not is_blocked_between(auth.uid(), uid) then
      insert into conversation_members(conversation_id, user_id) values (conv, uid)
        on conflict do nothing;
      if found then
        perform notify_user(uid, 'group_added', 'تمت إضافتك إلى مجموعة',
          coalesce(my_name, '') || ' أضافك إلى «' || coalesce(gname, '') || '»',
          jsonb_build_object('conversation_id', conv));
        insert into messages(conversation_id, sender_id, type, content)
          select conv, auth.uid(), 'system', 'أُضيف ' || display_name from profiles where id = uid;
      end if;
    end if;
  end loop;
end $$;

create or replace function public.remove_group_member(conv uuid, member uuid)
returns void language plpgsql security definer set search_path = public as $$
declare target_role text;
begin
  select role into target_role from conversation_members where conversation_id = conv and user_id = member;
  if target_role is null then return; end if;
  if member_role(conv) = 'owner' or (member_role(conv) = 'admin' and target_role = 'member') then
    delete from conversation_members where conversation_id = conv and user_id = member;
    insert into messages(conversation_id, sender_id, type, content)
      select conv, auth.uid(), 'system', 'أُزيل ' || display_name from profiles where id = member;
  else
    raise exception 'ليست لديك صلاحية';
  end if;
end $$;

create or replace function public.set_member_role(conv uuid, member uuid, new_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if member_role(conv) <> 'owner' then raise exception 'لمالك المجموعة فقط'; end if;
  if new_role not in ('admin','member') then raise exception 'دور غير صالح'; end if;
  update conversation_members set role = new_role
    where conversation_id = conv and user_id = member and role <> 'owner';
end $$;

create or replace function public.join_public_group(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if is_banned() then raise exception 'حسابك محظور'; end if;
  if not exists(select 1 from conversations where id = conv and type = 'group' and is_public) then
    raise exception 'المجموعة غير عامة';
  end if;
  insert into conversation_members(conversation_id, user_id) values (conv, auth.uid())
    on conflict do nothing;
end $$;

create or replace function public.leave_conversation(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r text; next_owner uuid;
begin
  r := member_role(conv);
  if r is null then return; end if;
  insert into messages(conversation_id, sender_id, type, content)
    select conv, auth.uid(), 'system', 'غادر ' || display_name from profiles where id = auth.uid();
  delete from conversation_members where conversation_id = conv and user_id = auth.uid();
  if r = 'owner' then
    select user_id into next_owner from conversation_members where conversation_id = conv
      order by (role = 'admin') desc, joined_at asc limit 1;
    if next_owner is null then
      delete from conversations where id = conv;
    else
      update conversation_members set role = 'owner' where conversation_id = conv and user_id = next_owner;
    end if;
  end if;
end $$;

create or replace function public.delete_group(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if member_role(conv) <> 'owner' and not is_admin() then raise exception 'لمالك المجموعة فقط'; end if;
  delete from conversations where id = conv and type = 'group';
end $$;

create or replace function public.set_conversation_flags(conv uuid, is_muted boolean, is_archived boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update conversation_members set
    muted = coalesce(is_muted, muted),
    archived = coalesce(is_archived, archived)
  where conversation_id = conv and user_id = auth.uid();
end $$;

create or replace function public.mark_read(conv uuid)
returns void language sql security definer set search_path = public as $$
  update conversation_members set last_read_at = now(), last_delivered_at = now()
  where conversation_id = conv and user_id = auth.uid();
$$;

create or replace function public.mark_all_delivered()
returns void language sql security definer set search_path = public as $$
  update conversation_members set last_delivered_at = now()
  where user_id = auth.uid();
  update profiles set last_seen = now() where id = auth.uid();
$$;

create or replace function public.touch_last_seen()
returns void language sql security definer set search_path = public as $$
  update profiles set last_seen = now() where id = auth.uid();
$$;

create or replace function public.edit_message(mid uuid, new_content text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update messages set content = new_content, edited_at = now()
  where id = mid and sender_id = auth.uid() and type = 'text' and not deleted;
  if not found then raise exception 'لا يمكن تعديل هذه الرسالة'; end if;
end $$;

create or replace function public.delete_message(mid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  select conversation_id into conv from messages where id = mid;
  update messages set deleted = true, content = null, media_path = null, file_name = null, pinned = false
  where id = mid and (sender_id = auth.uid() or member_role(conv) in ('owner','admin') or is_admin());
  if not found then raise exception 'لا يمكن حذف هذه الرسالة'; end if;
end $$;

create or replace function public.toggle_pin(mid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  select conversation_id into conv from messages where id = mid;
  if not is_member(conv) then raise exception 'غير مسموح'; end if;
  update messages set pinned = not pinned where id = mid and not deleted;
end $$;

drop function if exists public.get_my_conversations();
create function public.get_my_conversations()
returns table(
  id uuid, type text, name text, avatar_url text, is_public boolean,
  last_message_at timestamptz, last_message_preview text,
  muted boolean, archived boolean, my_role text, unread_count bigint,
  other_user_id uuid, other_username text, other_display_name text,
  other_avatar_url text, other_last_seen timestamptz, member_count bigint)
language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.name, c.avatar_url, c.is_public,
         c.last_message_at, c.last_message_preview,
         m.muted, m.archived, m.role,
         (select count(*) from messages x
            where x.conversation_id = c.id and x.created_at > m.last_read_at
              and x.sender_id is distinct from auth.uid() and not x.deleted and x.type <> 'system'),
         o.user_id, p.username, p.display_name, p.avatar_url, p.last_seen,
         (select count(*) from conversation_members z where z.conversation_id = c.id)
  from conversation_members m
  join conversations c on c.id = m.conversation_id
  left join lateral (
    select mm.user_id from conversation_members mm
    where mm.conversation_id = c.id and mm.user_id <> auth.uid() and c.type = 'direct'
    limit 1) o on true
  left join profiles p on p.id = o.user_id
  where m.user_id = auth.uid()
  order by c.last_message_at desc;
$$;

-- ---------------------------------------------------------------------
-- 5) RPC — جهات الاتصال
-- ---------------------------------------------------------------------

create or replace function public.send_contact_request(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare existing record;
begin
  if target = auth.uid() then raise exception 'لا يمكنك إضافة نفسك'; end if;
  if is_banned() then raise exception 'حسابك محظور'; end if;
  if is_blocked_between(auth.uid(), target) then raise exception 'لا يمكن الإرسال: يوجد حظر'; end if;
  select * into existing from contact_requests
    where least(sender_id, receiver_id) = least(auth.uid(), target)
      and greatest(sender_id, receiver_id) = greatest(auth.uid(), target);
  if existing.id is null then
    insert into contact_requests(sender_id, receiver_id) values (auth.uid(), target);
  elsif existing.status = 'rejected' then
    delete from contact_requests where id = existing.id;
    insert into contact_requests(sender_id, receiver_id) values (auth.uid(), target);
  elsif existing.status = 'pending' and existing.receiver_id = auth.uid() then
    update contact_requests set status = 'accepted', responded_at = now() where id = existing.id;
  end if;
end $$;

create or replace function public.respond_contact_request(req uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update contact_requests
    set status = case when accept then 'accepted' else 'rejected' end, responded_at = now()
  where id = req and receiver_id = auth.uid() and status = 'pending';
end $$;

create or replace function public.remove_contact(target uuid)
returns void language sql security definer set search_path = public as $$
  delete from contact_requests
  where least(sender_id, receiver_id) = least(auth.uid(), target)
    and greatest(sender_id, receiver_id) = greatest(auth.uid(), target);
$$;

create or replace function public.suggest_users(lim int default 10)
returns setof public.profiles
language sql stable security definer set search_path = public as $$
  select p.* from profiles p
  where p.id <> auth.uid() and not p.is_banned
    and not exists (select 1 from contact_requests r
      where least(r.sender_id, r.receiver_id) = least(auth.uid(), p.id)
        and greatest(r.sender_id, r.receiver_id) = greatest(auth.uid(), p.id))
    and not is_blocked_between(auth.uid(), p.id)
  order by
    (select count(*) from conversation_members a join conversation_members b
       on a.conversation_id = b.conversation_id
     where a.user_id = auth.uid() and b.user_id = p.id) desc,
    p.last_seen desc
  limit lim;
$$;

create or replace function public.common_groups(other uuid)
returns table(id uuid, name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.avatar_url from conversations c
  where c.type = 'group'
    and exists(select 1 from conversation_members where conversation_id = c.id and user_id = auth.uid())
    and exists(select 1 from conversation_members where conversation_id = c.id and user_id = other);
$$;

-- ---------------------------------------------------------------------
-- 6) RPC — الإدارة (Admin فقط)
-- ---------------------------------------------------------------------

create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  return jsonb_build_object(
    'users', (select count(*) from profiles),
    'active_24h', (select count(*) from profiles where last_seen > now() - interval '24 hours'),
    'active_5m', (select count(*) from profiles where last_seen > now() - interval '5 minutes'),
    'banned', (select count(*) from profiles where is_banned),
    'messages', (select count(*) from messages),
    'messages_24h', (select count(*) from messages where created_at > now() - interval '24 hours'),
    'groups', (select count(*) from conversations where type = 'group'),
    'open_reports', (select count(*) from reports where status = 'open'),
    'app_enabled', (select app_enabled from app_settings where id = 1)
  );
end $$;

create or replace function public.admin_set_app(enabled boolean, message text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  update app_settings set app_enabled = enabled,
    maintenance_message = coalesce(nullif(trim(message), ''), maintenance_message),
    updated_at = now()
  where id = 1;
end $$;

create or replace function public.admin_set_ban(target uuid, banned boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك حظر نفسك'; end if;
  update profiles set is_banned = banned where id = target;
end $$;

create or replace function public.admin_set_role(target uuid, make_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك تغيير صلاحيتك'; end if;
  update profiles set is_admin = make_admin where id = target;
end $$;

create or replace function public.admin_resolve_report(rid uuid, delete_msg boolean)
returns void language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  select message_id into mid from reports where id = rid;
  if delete_msg and mid is not null then
    update messages set deleted = true, content = null, media_path = null, file_name = null where id = mid;
  end if;
  update reports set status = 'resolved' where id = rid;
end $$;

create or replace function public.admin_broadcast(ntitle text, nbody text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  insert into notifications(user_id, type, title, body)
    select id, 'broadcast', ntitle, coalesce(nbody, '') from profiles where not is_banned;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.admin_list_groups()
returns table(id uuid, name text, avatar_url text, is_public boolean, member_count bigint,
              message_count bigint, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  return query
    select c.id, c.name, c.avatar_url, c.is_public,
      (select count(*) from conversation_members m where m.conversation_id = c.id),
      (select count(*) from messages x where x.conversation_id = c.id),
      c.created_at
    from conversations c where c.type = 'group' order by c.created_at desc limit 200;
end $$;

drop function if exists public.admin_list_reports();
create function public.admin_list_reports()
returns table(id uuid, reason text, status text, created_at timestamptz,
              reporter_username text, reported_username text, reported_user_id uuid,
              message_id uuid, message_content text, message_type text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  return query
    select r.id, r.reason, r.status, r.created_at,
      a.username, b.username, r.reported_user_id,
      r.message_id, m.content, m.type
    from reports r
    left join profiles a on a.id = r.reporter_id
    left join profiles b on b.id = r.reported_user_id
    left join messages m on m.id = r.message_id
    order by (r.status = 'open') desc, r.created_at desc limit 200;
end $$;

-- ---------------------------------------------------------------------
-- 7) Row Level Security
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.contact_requests enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());

-- app_settings: الكل يقرأ (حتى قبل تسجيل الدخول)، التعديل عبر admin_set_app فقط
drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings for select to anon, authenticated using (true);

-- conversations
drop policy if exists conv_select on public.conversations;
create policy conv_select on public.conversations for select to authenticated
  using (is_member(id) or (type = 'group' and is_public) or is_admin());

-- conversation_members
drop policy if exists members_select on public.conversation_members;
create policy members_select on public.conversation_members for select to authenticated
  using (is_member(conversation_id) or is_admin());

-- messages
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select to authenticated
  using (is_member(conversation_id) or is_admin());
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and type <> 'system' and can_send(conversation_id));

-- contact_requests
drop policy if exists cr_select on public.contact_requests;
create policy cr_select on public.contact_requests for select to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid());

-- blocks
drop policy if exists blocks_select on public.blocks;
create policy blocks_select on public.blocks for select to authenticated
  using (blocker_id = auth.uid());
drop policy if exists blocks_insert on public.blocks;
create policy blocks_insert on public.blocks for insert to authenticated
  with check (blocker_id = auth.uid());
drop policy if exists blocks_delete on public.blocks;
create policy blocks_delete on public.blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- reports
drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = auth.uid());
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated
  using (reporter_id = auth.uid() or is_admin());

-- notifications
drop policy if exists notif_select on public.notifications;
create policy notif_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists notif_delete on public.notifications;
create policy notif_delete on public.notifications for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 8) Storage
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
  values ('avatars', 'avatars', true, 5242880)
  on conflict (id) do update set public = true, file_size_limit = 5242880;
insert into storage.buckets (id, name, public, file_size_limit)
  values ('chat-media', 'chat-media', false, 52428800)
  on conflict (id) do update set public = false, file_size_limit = 52428800;

-- avatars: المسار <user_id>/... أو groups/<conversation_id>/...
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select
  using (bucket_id = 'avatars');
drop policy if exists avatars_write on storage.objects;
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or ((storage.foldername(name))[1] = 'groups'
        and public.member_role(((storage.foldername(name))[2])::uuid) in ('owner','admin'))));
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and owner = auth.uid());
drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and owner = auth.uid());

-- chat-media: المسار <conversation_id>/<file> — أعضاء المحادثة فقط
drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'chat-media'
         and (public.is_member(((storage.foldername(name))[1])::uuid) or public.is_admin()));
drop policy if exists media_write on storage.objects;
create policy media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media'
              and public.can_send(((storage.foldername(name))[1])::uuid));

-- ---------------------------------------------------------------------
-- 9) Realtime
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['messages','conversations','conversation_members',
                           'notifications','app_settings','contact_requests'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- لإرسال السجل القديم في أحداث UPDATE
alter table public.messages replica identity full;
alter table public.conversation_members replica identity full;

-- ---------------------------------------------------------------------
-- 10) صلاحيات الدوال
-- ---------------------------------------------------------------------
grant execute on function public.username_available(text) to anon, authenticated;


-- =====================================================================
--  الإصدار 2: المالك، المستويات (XP)، التوثيق، المنشورات
-- =====================================================================

alter table public.profiles add column if not exists xp int not null default 0;
alter table public.profiles add column if not exists is_verified boolean not null default false;
alter table public.profiles add column if not exists is_owner boolean not null default false;

create table if not exists public.xp_daily (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default current_date,
  msg_xp int not null default 0,
  post_xp int not null default 0,
  comment_xp int not null default 0,
  primary key (user_id, day)
);
alter table public.xp_daily enable row level security;

create or replace function public.xp_level(x int) returns int
language sql immutable as $$ select least(100, greatest(0, coalesce(x, 0)) / 100 + 1); $$;

-- عمليات داخلية موثوقة تتجاوز حماية الأعمدة
create or replace function public.trusted_begin() returns void
language sql as $$ select set_config('app.trusted', '1', true); $$;

create or replace function public.protect_profile_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and coalesce(current_setting('app.trusted', true), '') <> '1'
     and not is_admin() then
    new.is_admin := old.is_admin;
    new.is_banned := old.is_banned;
    new.is_verified := old.is_verified;
    new.xp := old.xp;
  end if;
  -- لا أحد يغيّر صفة المالك إلا من SQL Editor
  if auth.uid() is not null and coalesce(current_setting('app.trusted', true), '') <> '1' then
    new.is_owner := old.is_owner;
  end if;
  if old.is_owner and auth.uid() is distinct from old.id and auth.uid() is not null
     and coalesce(current_setting('app.trusted', true), '') <> '1' then
    new.is_admin := true;
    new.is_banned := false;
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  new.username := lower(new.username);
  return new;
end $$;

create or replace function public.add_xp(uid uuid, amount int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if uid is null or amount = 0 then return; end if;
  perform trusted_begin();
  update profiles set xp = greatest(0, xp + amount),
    is_verified = is_verified or xp_level(greatest(0, xp + amount)) >= 50
  where id = uid;
  perform set_config('app.trusted', '', true);
end $$;
revoke execute on function public.add_xp(uuid, int) from public, anon, authenticated;

-- نقاط بحد يومي
create or replace function public.add_capped_xp(uid uuid, kind text, amount int, cap int) returns void
language plpgsql security definer set search_path = public as $$
declare used int;
begin
  insert into xp_daily(user_id, day) values (uid, current_date) on conflict do nothing;
  execute format('update xp_daily set %I = %I + $1 where user_id = $2 and day = current_date returning %I',
                 kind, kind, kind) into used using amount, uid;
  if used <= cap then perform add_xp(uid, amount); end if;
end $$;
revoke execute on function public.add_capped_xp(uuid, text, int, int) from public, anon, authenticated;

-- أول حساب في التطبيق = المالك (مدير + موثّق)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uname text := lower(coalesce(new.raw_user_meta_data->>'username', ''));
  first_user boolean := not exists(select 1 from profiles where is_owner);
begin
  if uname !~ '^[a-z0-9_.]{3,24}$' or exists(select 1 from profiles where username = uname) then
    uname := 'user_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  insert into profiles(id, username, display_name, is_admin, is_owner, is_verified)
  values (new.id, uname,
          coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), uname),
          first_user, first_user, first_user);
  return new;
end $$;

-- إذا كانت هناك حسابات سابقة بلا مالك: أقدم حساب يصبح المالك
do $$
begin
  if not exists(select 1 from public.profiles where is_owner) then
    update public.profiles set is_owner = true, is_admin = true, is_verified = true
    where id = (select id from public.profiles order by created_at asc limit 1);
  end if;
end $$;
update public.profiles set is_verified = true, is_admin = true where is_owner;

-- XP من الرسائل (+1، حد 50 يوميًا)
create or replace function public.xp_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type <> 'system' and new.sender_id is not null then
    perform add_capped_xp(new.sender_id, 'msg_xp', 1, 50);
  end if;
  return new;
end $$;
drop trigger if exists trg_xp_message on public.messages;
create trigger trg_xp_message after insert on public.messages
  for each row execute function public.xp_on_message();

-- XP عند قبول طلب تواصل (+5 للطرفين)
create or replace function public.xp_on_contact() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'accepted' and old.status <> 'accepted' then
    perform add_xp(new.sender_id, 5);
    perform add_xp(new.receiver_id, 5);
  end if;
  return new;
end $$;
drop trigger if exists trg_xp_contact on public.contact_requests;
create trigger trg_xp_contact after update on public.contact_requests
  for each row execute function public.xp_on_contact();

-- ---------------------------------------------------------------------
-- المنشورات
-- ---------------------------------------------------------------------
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null default '' check (char_length(content) <= 3000),
  image_url text,
  like_count int not null default 0,
  comment_count int not null default 0,
  deleted boolean not null default false,
  created_at timestamptz not null default now(),
  check (char_length(content) > 0 or image_url is not null)
);
create index if not exists idx_posts_created on public.posts(created_at desc) where not deleted;
create index if not exists idx_posts_author on public.posts(author_id, created_at desc);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists idx_post_likes_user on public.post_likes(user_id);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists idx_comments_post on public.post_comments(post_id, created_at);

alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;

create or replace function public.can_post() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and not is_banned()
     and ((select app_enabled from app_settings where id = 1) or is_admin());
$$;

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select to authenticated
  using ((not deleted and not is_blocked_between(auth.uid(), author_id)) or is_admin());
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id = auth.uid() and can_post());

drop policy if exists likes_select on public.post_likes;
create policy likes_select on public.post_likes for select to authenticated using (true);
drop policy if exists likes_insert on public.post_likes;
create policy likes_insert on public.post_likes for insert to authenticated
  with check (user_id = auth.uid() and can_post());
drop policy if exists likes_delete on public.post_likes;
create policy likes_delete on public.post_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists comments_select on public.post_comments;
create policy comments_select on public.post_comments for select to authenticated
  using (not is_blocked_between(auth.uid(), author_id) or is_admin());
drop policy if exists comments_insert on public.post_comments;
create policy comments_insert on public.post_comments for insert to authenticated
  with check (author_id = auth.uid() and can_post());

-- حماية الأعمدة المحسوبة + منع الإغراق
create or replace function public.before_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from posts where author_id = new.author_id
      and created_at > now() - interval '1 minute') >= 3 then
    raise exception 'rate_limited: انتظر قليلًا قبل نشر منشور جديد';
  end if;
  new.like_count := 0; new.comment_count := 0; new.deleted := false; new.created_at := now();
  return new;
end $$;
drop trigger if exists trg_before_post on public.posts;
create trigger trg_before_post before insert on public.posts
  for each row execute function public.before_post_insert();

create or replace function public.after_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform add_capped_xp(new.author_id, 'post_xp', 10, 50);
  return new;
end $$;
drop trigger if exists trg_after_post on public.posts;
create trigger trg_after_post after insert on public.posts
  for each row execute function public.after_post_insert();

create or replace function public.on_like_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare author uuid; liker_name text;
begin
  if tg_op = 'INSERT' then
    update posts set like_count = like_count + 1 where id = new.post_id returning author_id into author;
    if author is not null and author <> new.user_id then
      perform add_xp(author, 2);
      select display_name into liker_name from profiles where id = new.user_id;
      perform notify_user(author, 'post_like', 'إعجاب جديد',
        coalesce(liker_name, '') || ' أعجبه منشورك', jsonb_build_object('post_id', new.post_id));
    end if;
    return new;
  else
    update posts set like_count = greatest(0, like_count - 1) where id = old.post_id;
    return old;
  end if;
end $$;
drop trigger if exists trg_like_change on public.post_likes;
create trigger trg_like_change after insert or delete on public.post_likes
  for each row execute function public.on_like_change();

create or replace function public.on_comment_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare author uuid; n text;
begin
  if tg_op = 'INSERT' then
    if (select count(*) from post_comments where author_id = new.author_id
        and created_at > now() - interval '30 seconds') > 5 then
      raise exception 'rate_limited: تعليقات كثيرة بسرعة';
    end if;
    update posts set comment_count = comment_count + 1 where id = new.post_id returning author_id into author;
    perform add_capped_xp(new.author_id, 'comment_xp', 3, 30);
    if author is not null and author <> new.author_id then
      perform add_xp(author, 2);
      select display_name into n from profiles where id = new.author_id;
      perform notify_user(author, 'post_comment', 'تعليق جديد',
        coalesce(n, '') || ': ' || left(new.content, 80), jsonb_build_object('post_id', new.post_id));
    end if;
    return new;
  else
    update posts set comment_count = greatest(0, comment_count - 1) where id = old.post_id;
    return old;
  end if;
end $$;
drop trigger if exists trg_comment_change on public.post_comments;
create trigger trg_comment_change after insert or delete on public.post_comments
  for each row execute function public.on_comment_change();

create or replace function public.delete_post(pid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update posts set deleted = true
  where id = pid and (author_id = auth.uid() or is_admin());
  if not found then raise exception 'لا يمكن حذف هذا المنشور'; end if;
end $$;

create or replace function public.delete_comment(cid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from post_comments c
  where c.id = cid and (c.author_id = auth.uid() or is_admin()
        or exists(select 1 from posts p where p.id = c.post_id and p.author_id = auth.uid()));
  if not found then raise exception 'لا يمكن حذف هذا التعليق'; end if;
end $$;

-- صورة المنشورات: bucket عام، الكتابة في مجلد المستخدم فقط
insert into storage.buckets (id, name, public, file_size_limit)
  values ('posts', 'posts', true, 10485760)
  on conflict (id) do update set public = true, file_size_limit = 10485760;
drop policy if exists posts_read on storage.objects;
create policy posts_read on storage.objects for select using (bucket_id = 'posts');
drop policy if exists posts_write on storage.objects;
create policy posts_write on storage.objects for insert to authenticated
  with check (bucket_id = 'posts' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- تحديثات الدوال للإصدار 2
-- ---------------------------------------------------------------------
drop function if exists public.get_my_conversations();
create function public.get_my_conversations()
returns table(
  id uuid, type text, name text, avatar_url text, is_public boolean,
  last_message_at timestamptz, last_message_preview text,
  muted boolean, archived boolean, my_role text, unread_count bigint,
  other_user_id uuid, other_username text, other_display_name text,
  other_avatar_url text, other_last_seen timestamptz, member_count bigint,
  other_verified boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.name, c.avatar_url, c.is_public,
         c.last_message_at, c.last_message_preview,
         m.muted, m.archived, m.role,
         (select count(*) from messages x
            where x.conversation_id = c.id and x.created_at > m.last_read_at
              and x.sender_id is distinct from auth.uid() and not x.deleted and x.type <> 'system'),
         o.user_id, p.username, p.display_name, p.avatar_url, p.last_seen,
         (select count(*) from conversation_members z where z.conversation_id = c.id),
         coalesce(p.is_verified, false)
  from conversation_members m
  join conversations c on c.id = m.conversation_id
  left join lateral (
    select mm.user_id from conversation_members mm
    where mm.conversation_id = c.id and mm.user_id <> auth.uid() and c.type = 'direct'
    limit 1) o on true
  left join profiles p on p.id = o.user_id
  where m.user_id = auth.uid()
  order by c.last_message_at desc;
$$;

create or replace function public.get_owner_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from profiles where is_owner order by created_at limit 1;
$$;

create or replace function public.admin_set_ban(target uuid, banned boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك حظر نفسك'; end if;
  if exists(select 1 from profiles where id = target and is_owner) then raise exception 'لا يمكن حظر مالك التطبيق'; end if;
  update profiles set is_banned = banned where id = target;
end $$;

create or replace function public.admin_set_role(target uuid, make_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك تغيير صلاحيتك'; end if;
  if exists(select 1 from profiles where id = target and is_owner) then raise exception 'لا يمكن تغيير صلاحية المالك'; end if;
  update profiles set is_admin = make_admin where id = target;
end $$;

create or replace function public.admin_set_verified(target uuid, verified boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if exists(select 1 from profiles where id = target and is_owner) and not verified then
    raise exception 'المالك موثّق دائمًا';
  end if;
  update profiles set is_verified = verified where id = target;
end $$;

create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  return jsonb_build_object(
    'users', (select count(*) from profiles),
    'active_24h', (select count(*) from profiles where last_seen > now() - interval '24 hours'),
    'active_5m', (select count(*) from profiles where last_seen > now() - interval '5 minutes'),
    'banned', (select count(*) from profiles where is_banned),
    'verified', (select count(*) from profiles where is_verified),
    'messages', (select count(*) from messages),
    'messages_24h', (select count(*) from messages where created_at > now() - interval '24 hours'),
    'posts', (select count(*) from posts where not deleted),
    'posts_24h', (select count(*) from posts where not deleted and created_at > now() - interval '24 hours'),
    'groups', (select count(*) from conversations where type = 'group'),
    'open_reports', (select count(*) from reports where status = 'open'),
    'app_enabled', (select app_enabled from app_settings where id = 1)
  );
end $$;

do $$
declare t text;
begin
  foreach t in array array['posts','post_likes','post_comments'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;


-- =====================================================================
--  الإصدار 3: الإنذارات، الإبلاغ عن المنشورات، تعديل المنشورات، الإشارات
-- =====================================================================

alter table public.profiles add column if not exists warnings int not null default 0;
alter table public.reports add column if not exists post_id uuid references public.posts(id) on delete set null;
alter table public.posts add column if not exists edited_at timestamptz;

-- حماية عمود الإنذارات من تعديل المستخدم
create or replace function public.protect_profile_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and coalesce(current_setting('app.trusted', true), '') <> '1'
     and not is_admin() then
    new.is_admin := old.is_admin;
    new.is_banned := old.is_banned;
    new.is_verified := old.is_verified;
    new.xp := old.xp;
    new.warnings := old.warnings;
  end if;
  if auth.uid() is not null and coalesce(current_setting('app.trusted', true), '') <> '1' then
    new.is_owner := old.is_owner;
  end if;
  if old.is_owner and auth.uid() is not null
     and coalesce(current_setting('app.trusted', true), '') <> '1' then
    new.is_admin := true;
    new.is_banned := false;
    new.warnings := 0;
  end if;
  new.id := old.id;
  new.created_at := old.created_at;
  new.username := lower(new.username);
  return new;
end $$;

-- إنذار: 1 و 2 و 3 تحذير، الرابع = حظر نهائي
create or replace function public.admin_warn(target uuid, reason text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if exists(select 1 from profiles where id = target and is_owner) then raise exception 'لا يمكن إنذار المالك'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك إنذار نفسك'; end if;
  update profiles set warnings = warnings + 1,
         is_banned = is_banned or warnings + 1 >= 4
  where id = target returning warnings into n;
  if n is null then raise exception 'المستخدم غير موجود'; end if;
  if n >= 4 then
    insert into notifications(user_id, type, title, body)
      values (target, 'warning', '⛔ تم حظر حسابك', 'تم إيقاف حسابك نهائيًا بعد 4 إنذارات. السبب: ' || coalesce(reason, ''));
  else
    insert into notifications(user_id, type, title, body)
      values (target, 'warning', '⚠️ إنذار رقم ' || n || ' من 3',
              'السبب: ' || coalesce(reason, '') || '. عند الإنذار الرابع سيتم حظر حسابك نهائيًا.');
  end if;
  return n;
end $$;

create or replace function public.admin_clear_warnings(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  update profiles set warnings = 0 where id = target;
end $$;

create or replace function public.admin_set_ban(target uuid, banned boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if target = auth.uid() then raise exception 'لا يمكنك حظر نفسك'; end if;
  if exists(select 1 from profiles where id = target and is_owner) then raise exception 'لا يمكن حظر مالك التطبيق'; end if;
  update profiles set is_banned = banned,
         warnings = case when banned then warnings else 0 end
  where id = target;
end $$;

-- تعديل المنشور (صاحبه فقط)
create or replace function public.edit_post(pid uuid, new_content text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(new_content, '')) > 3000 then raise exception 'النص طويل جدًا'; end if;
  update posts set content = coalesce(new_content, ''), edited_at = now()
  where id = pid and author_id = auth.uid() and not deleted
    and (char_length(coalesce(new_content, '')) > 0 or image_url is not null);
  if not found then raise exception 'لا يمكن تعديل هذا المنشور'; end if;
end $$;

-- الإشارة إلى الأشخاص (@username) في المنشورات والتعليقات
create or replace function public.notify_mentions(txt text, actor uuid, ptitle text, pdata jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare mention text; target uuid; actor_name text;
begin
  if txt is null or position('@' in txt) = 0 then return; end if;
  select display_name into actor_name from profiles where id = actor;
  for mention in
    select distinct lower(m[1]) from regexp_matches(txt, '@([A-Za-z0-9_.]{3,24})', 'g') as m
  loop
    select id into target from profiles where username = mention and id <> actor;
    if target is not null and not is_blocked_between(actor, target) then
      perform notify_user(target, 'mention', coalesce(actor_name, '') || ' ' || ptitle, left(txt, 120), pdata);
    end if;
    target := null;
  end loop;
end $$;
revoke execute on function public.notify_mentions(text, uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.after_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform add_capped_xp(new.author_id, 'post_xp', 10, 50);
  perform notify_mentions(new.content, new.author_id, 'أشار إليك في منشور', jsonb_build_object('post_id', new.id));
  return new;
end $$;

create or replace function public.mention_on_comment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_mentions(new.content, new.author_id, 'أشار إليك في تعليق', jsonb_build_object('post_id', new.post_id));
  return new;
end $$;
drop trigger if exists trg_comment_mention on public.post_comments;
create trigger trg_comment_mention after insert on public.post_comments
  for each row execute function public.mention_on_comment();

drop function if exists public.admin_list_reports();
create function public.admin_list_reports()
returns table(id uuid, reason text, status text, created_at timestamptz,
              reporter_username text, reported_username text, reported_user_id uuid,
              reported_warnings int, reported_banned boolean,
              message_id uuid, message_content text, message_type text,
              post_id uuid, post_content text, post_image text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  return query
    select r.id, r.reason, r.status, r.created_at,
      a.username, b.username, r.reported_user_id,
      coalesce(b.warnings, 0), coalesce(b.is_banned, false),
      r.message_id, m.content, m.type,
      r.post_id, p.content, p.image_url
    from reports r
    left join profiles a on a.id = r.reporter_id
    left join profiles b on b.id = r.reported_user_id
    left join messages m on m.id = r.message_id
    left join posts p on p.id = r.post_id
    order by (r.status = 'open') desc, r.created_at desc limit 200;
end $$;

create or replace function public.admin_resolve_report(rid uuid, delete_msg boolean)
returns void language plpgsql security definer set search_path = public as $$
declare mid uuid; pid uuid;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  select message_id, post_id into mid, pid from reports where id = rid;
  if delete_msg then
    if mid is not null then
      update messages set deleted = true, content = null, media_path = null, file_name = null where id = mid;
    end if;
    if pid is not null then
      update posts set deleted = true where id = pid;
    end if;
  end if;
  update reports set status = 'resolved' where id = rid;
end $$;


-- =====================================================================
--  الإصدار 4: إعدادات سرية (بيانات الخادم الوسيط للمكالمات)
--  محفوظة داخل قاعدة البيانات فقط — لا تظهر في التطبيق ولا في GitHub
-- =====================================================================

create table if not exists public.private_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.private_settings enable row level security;
-- لا توجد أي سياسة قراءة: الجدول مغلق تمامًا إلا عبر الدوال أدناه

create or replace function public.admin_set_turn(turn_user text, turn_pass text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_admin() then raise exception 'للمدير فقط'; end if;
  if char_length(coalesce(turn_user, '')) < 5 or char_length(coalesce(turn_pass, '')) < 5 then
    raise exception 'بيانات غير صالحة';
  end if;
  insert into private_settings(key, value) values ('turn_user', trim(turn_user))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into private_settings(key, value) values ('turn_pass', trim(turn_pass))
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

create or replace function public.admin_turn_status() returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() and exists(select 1 from private_settings where key = 'turn_user');
$$;

-- يُعطى فقط لمستخدم مسجّل وغير محظور، ولحظة المكالمة فقط
create or replace function public.get_ice_servers() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u text; p text;
begin
  if auth.uid() is null or is_banned() then return '[]'::jsonb; end if;
  select value into u from private_settings where key = 'turn_user';
  select value into p from private_settings where key = 'turn_pass';
  if u is null or p is null then return '[]'::jsonb; end if;
  return jsonb_build_array(jsonb_build_object(
    'urls', jsonb_build_array(
      'turn:global.relay.metered.ca:80',
      'turn:global.relay.metered.ca:80?transport=tcp',
      'turn:global.relay.metered.ca:443',
      'turns:global.relay.metered.ca:443?transport=tcp'),
    'username', u,
    'credential', p));
end $$;
revoke execute on function public.get_ice_servers() from anon;


-- =====================================================================
--  الإصدار 5: المدير يعيّن كلمة مرور جديدة لمستخدم (بديل عند تعذّر الإيميل)
-- =====================================================================
create or replace function public.admin_set_password(target uuid, new_password text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if char_length(coalesce(new_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  if exists(select 1 from profiles where id = target and is_owner) and target <> auth.uid() then
    raise exception 'لا يمكن تغيير كلمة مرور المالك';
  end if;
  update auth.users set encrypted_password = crypt(new_password, gen_salt('bf')), updated_at = now()
  where id = target;
  if not found then raise exception 'المستخدم غير موجود'; end if;
end $$;


-- =====================================================================
--  الإصدار 6: إنشاء حساب واستعادة كلمة المرور بدون الاعتماد على الإيميل
-- =====================================================================

create table if not exists public.signup_attempts (ip text not null, at timestamptz not null default now());
create table if not exists public.recovery_codes (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  code_hash text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.recovery_attempts (username text not null, at timestamptz not null default now());
alter table public.signup_attempts enable row level security;
alter table public.recovery_codes enable row level security;
alter table public.recovery_attempts enable row level security;

create or replace function public.request_ip() returns text
language plpgsql stable as $$
declare h json;
begin
  begin h := current_setting('request.headers', true)::json; exception when others then return 'unknown'; end;
  return coalesce(split_part(coalesce(h->>'cf-connecting-ip', h->>'x-forwarded-for', h->>'x-real-ip'), ',', 1), 'unknown');
end $$;

-- تسجيل مباشر (حساب مؤكد) — يُستخدم عندما يتعذر إرسال إيميل التأكيد
create or replace function public.register_user(p_email text, p_password text, p_username text, p_display text)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  em text := lower(trim(coalesce(p_email, '')));
  un text := lower(trim(coalesce(p_username, '')));
  dn text := trim(coalesce(p_display, ''));
  v_ip text := request_ip();
  uid uuid;
  confirmed timestamptz;
begin
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صالح'; end if;
  if char_length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  if un !~ '^[a-z0-9_.]{3,24}$' then raise exception 'اسم المستخدم غير صالح'; end if;
  if dn = '' then dn := un; end if;

  -- حماية من الإغراق
  delete from signup_attempts where at < now() - interval '1 day';
  if (select count(*) from signup_attempts where ip = v_ip and at > now() - interval '1 hour') >= 5
     or (select count(*) from signup_attempts where at > now() - interval '1 hour') >= 200 then
    raise exception 'rate_limited: محاولات كثيرة، حاول لاحقًا';
  end if;
  insert into signup_attempts(ip) values (v_ip);

  select id, email_confirmed_at into uid, confirmed from auth.users where lower(email) = em limit 1;
  if uid is not null and confirmed is not null then raise exception 'هذا البريد مسجّل مسبقًا'; end if;
  if exists(select 1 from profiles where username = un and id is distinct from uid) then
    raise exception 'اسم المستخدم محجوز، اختر اسمًا آخر';
  end if;

  if uid is not null then
    -- حساب سابق لم يُؤكَّد (فشل إيميل التأكيد): نؤكده ونحدّث بياناته
    update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')),
           email_confirmed_at = now(), updated_at = now(),
           raw_user_meta_data = jsonb_build_object('username', un, 'display_name', dn)
    where id = uid;
    perform trusted_begin();
    update profiles set username = un, display_name = dn where id = uid;
    perform set_config('app.trusted', '', true);
  else
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
            crypt(p_password, gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('username', un, 'display_name', dn), now(), now(), '', '', '', '');
  end if;

  if not exists(select 1 from auth.identities where user_id = uid and provider = 'email') then
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
            'email', now(), now(), now());
  end if;
  return uid;
end $$;
grant execute on function public.register_user(text, text, text, text) to anon, authenticated;

-- رمز الاسترداد: يُنشئه المستخدم من الإعدادات ويحتفظ به، ويستعمله إذا نسي كلمة المرور
create or replace function public.create_recovery_code() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare raw text; pretty text;
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولًا'; end if;
  raw := upper(substr(encode(gen_random_bytes(10), 'hex'), 1, 12));
  pretty := substr(raw, 1, 4) || '-' || substr(raw, 5, 4) || '-' || substr(raw, 9, 4);
  insert into recovery_codes(user_id, code_hash) values (auth.uid(), crypt(raw, gen_salt('bf')))
    on conflict (user_id) do update set code_hash = excluded.code_hash, created_at = now();
  return pretty;
end $$;

create or replace function public.has_recovery_code() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from recovery_codes where user_id = auth.uid());
$$;

create or replace function public.reset_password_with_code(p_username text, p_code text, p_new_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
declare un text := lower(trim(coalesce(p_username, ''))); uid uuid; h text; em text;
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if char_length(coalesce(p_new_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  delete from recovery_attempts where at < now() - interval '1 day';
  if (select count(*) from recovery_attempts where username = un and at > now() - interval '1 hour') >= 5 then
    raise exception 'rate_limited: محاولات كثيرة، حاول بعد ساعة';
  end if;
  insert into recovery_attempts(username) values (un);
  select p.id into uid from profiles p where p.username = un and not p.is_banned;
  select code_hash into h from recovery_codes where user_id = uid;
  if uid is null or h is null or crypt(code, h) <> h then
    raise exception 'اسم المستخدم أو رمز الاسترداد غير صحيح';
  end if;
  update auth.users set encrypted_password = crypt(p_new_password, gen_salt('bf')), updated_at = now()
    where id = uid returning email into em;
  delete from recovery_codes where user_id = uid; -- الرمز يُستخدم مرة واحدة
  return em;
end $$;
grant execute on function public.reset_password_with_code(text, text, text) to anon, authenticated;

-- =====================================================================
--  الإصدار 7: إشارات المكالمات عبر قاعدة البيانات (لا تضيع مهما كانت الشبكة)
--  + تحديث تلقائي لقاعدة البيانات من GitHub (لا حاجة لتشغيل السكربت يدويًا مستقبلًا)
-- =====================================================================

create table if not exists public.call_sessions (
  id uuid primary key,
  caller uuid not null references auth.users(id) on delete cascade,
  callee uuid not null references auth.users(id) on delete cascade,
  video boolean not null default false,
  status text not null default 'ringing',  -- ringing, accepted, rejected, busy, ended
  offer jsonb,
  answer jsonb,
  caller_ice jsonb not null default '[]'::jsonb,
  callee_ice jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists call_sessions_callee_idx on public.call_sessions(callee, created_at desc);
alter table public.call_sessions enable row level security;

drop policy if exists call_sessions_select on public.call_sessions;
create policy call_sessions_select on public.call_sessions for select to authenticated
  using (auth.uid() in (caller, callee));

-- لا إدخال/تعديل مباشر: فقط عبر الدوال أدناه
create or replace function public.call_create(p_id uuid, p_callee uuid, p_video boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or is_banned() then raise exception 'غير مسموح'; end if;
  if exists(select 1 from blocks where (blocker_id = p_callee and blocked_id = auth.uid())
                                    or (blocker_id = auth.uid() and blocked_id = p_callee)) then
    raise exception 'لا يمكن الاتصال بهذا المستخدم';
  end if;
  if (select count(*) from call_sessions where caller = auth.uid() and created_at > now() - interval '1 minute') >= 6 then
    raise exception 'rate_limited: مكالمات كثيرة، انتظر قليلًا';
  end if;
  delete from call_sessions where created_at < now() - interval '2 days';
  insert into call_sessions(id, caller, callee, video) values (p_id, auth.uid(), p_callee, coalesce(p_video, false));
end $$;

-- تحديث حقل في المكالمة: الحالة، العرض (للمتصل)، الرد (للمستقبل)، أو إضافة عنوان شبكة
create or replace function public.call_update(p_id uuid, p_status text default null, p_offer jsonb default null,
  p_answer jsonb default null, p_ice jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare c call_sessions;
begin
  select * into c from call_sessions where id = p_id;
  if c.id is null or auth.uid() not in (c.caller, c.callee) then raise exception 'مكالمة غير موجودة'; end if;
  if p_status is not null and p_status not in ('accepted', 'rejected', 'busy', 'ended') then
    raise exception 'حالة غير صالحة';
  end if;
  update call_sessions set
    status = case when p_status is null or status = 'ended' then status else p_status end,
    offer = case when auth.uid() = c.caller and p_offer is not null then p_offer else offer end,
    answer = case when auth.uid() = c.callee and p_answer is not null then p_answer else answer end,
    caller_ice = case when auth.uid() = c.caller and p_ice is not null and jsonb_array_length(caller_ice) < 60
                      then caller_ice || jsonb_build_array(p_ice) else caller_ice end,
    callee_ice = case when auth.uid() = c.callee and p_ice is not null and jsonb_array_length(callee_ice) < 60
                      then callee_ice || jsonb_build_array(p_ice) else callee_ice end,
    updated_at = now()
  where id = p_id;
end $$;

-- مكالمات واردة لم يُرد عليها (احتياطي إذا لم تصل الدعوة الفورية)
create or replace function public.call_pending() returns setof public.call_sessions
language sql stable security definer set search_path = public as $$
  select * from call_sessions
  where callee = auth.uid() and status = 'ringing' and created_at > now() - interval '40 seconds'
  order by created_at desc limit 1;
$$;

grant execute on function public.call_create(uuid, uuid, boolean) to authenticated;
grant execute on function public.call_update(uuid, text, jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.call_pending() to authenticated;
revoke execute on function public.call_create(uuid, uuid, boolean) from anon;
revoke execute on function public.call_update(uuid, text, jsonb, jsonb, jsonb) from anon;
revoke execute on function public.call_pending() from anon;

do $$
begin
  execute 'alter publication supabase_realtime add table public.call_sessions';
exception when duplicate_object then null; when others then null;
end $$;

-- تحديث تلقائي: كل 10 دقائق يجلب هذا الملف من GitHub ويطبّقه فقط إذا تغيّر
create or replace function public._auto_update_schema() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare body text; h text; old text;
begin
  select content into body from extensions.http_get(
    'https://raw.githubusercontent.com/almajhool-dev/almajhool-ap/main/supabase/schema.sql');
  if body is null or position('notify pgrst' in body) = 0 then return 'skip'; end if;
  h := md5(body);
  select value into old from private_settings where key = 'schema_hash';
  if old = h then return 'same'; end if;
  execute body;
  insert into private_settings(key, value) values ('schema_hash', h)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return 'updated';
end $$;
revoke execute on function public._auto_update_schema() from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('almajhool-auto-update', '*/10 * * * *', 'select public._auto_update_schema()');
exception when others then raise notice 'auto update not scheduled: %', sqlerrm;
end $$;

-- =====================================================================
--  الإصدار 8: استقبال المكالمات والرسائل والتطبيق مغلق (خدمة الخلفية)
--  كل جهاز له مفتاح سري عشوائي؛ الخادم يرسل «تنبيه» فارغ والجهاز يسأل عن التفاصيل.
-- =====================================================================

create table if not exists public.device_tokens (
  token text primary key check (char_length(token) between 32 and 100),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_poll timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;
-- لا سياسات: الوصول فقط عبر الدوال

create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'غير مسموح'; end if;
  insert into device_tokens(token, user_id) values (p_token, auth.uid())
    on conflict (token) do update set user_id = excluded.user_id, last_poll = now();
  -- حد أقصى 5 أجهزة لكل مستخدم
  delete from device_tokens where user_id = auth.uid() and token not in (
    select token from device_tokens where user_id = auth.uid() order by last_poll desc limit 5);
end $$;

create or replace function public.unregister_device(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from device_tokens where token = p_token;
$$;

create or replace function public.bg_poll(p_token text, p_since timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid; calls jsonb; msgs jsonb;
begin
  select d.user_id into uid from device_tokens d where d.token = p_token;
  if uid is null or exists(select 1 from profiles where id = uid and is_banned) then
    return jsonb_build_object('invalid', true);
  end if;
  update device_tokens set last_poll = now() where token = p_token;

  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', p.display_name, 'video', c.video)), '[]'::jsonb)
    into calls
  from call_sessions c join profiles p on p.id = c.caller
  where c.callee = uid and c.status = 'ringing' and c.created_at > now() - interval '45 seconds';

  select coalesce(jsonb_agg(x order by x->>'created_at'), '[]'::jsonb) into msgs from (
    select jsonb_build_object(
      'conversation_id', m.conversation_id,
      'created_at', to_char(m.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'title', case when cv.type = 'group' then coalesce(cv.name, 'مجموعة') else coalesce(sp.display_name, 'رسالة جديدة') end,
      'body', case when cv.type = 'group' then coalesce(sp.display_name, '') || ': ' else '' end ||
        case when m.deleted then 'رسالة محذوفة'
             when m.type = 'image' then '📷 صورة'
             when m.type = 'video' then '🎬 فيديو'
             when m.type = 'audio' then '🎤 رسالة صوتية'
             when m.type = 'file' then '📎 ' || coalesce(m.file_name, 'ملف')
             else left(coalesce(m.content, ''), 200) end
    ) as x
    from messages m
    join conversation_members cm on cm.conversation_id = m.conversation_id and cm.user_id = uid
    join conversations cv on cv.id = m.conversation_id
    left join profiles sp on sp.id = m.sender_id
    where m.created_at > greatest(coalesce(p_since, now()), now() - interval '1 day')
      and m.sender_id is distinct from uid and m.type <> 'system' and not cm.muted
      and not exists(select 1 from blocks b where b.blocker_id = uid and b.blocked_id = m.sender_id)
    order by m.created_at desc limit 20
  ) t;

  return jsonb_build_object('calls', calls, 'messages', msgs, 'push_ok', push_ready());
end $$;

grant execute on function public.register_device(text) to authenticated;
grant execute on function public.unregister_device(text) to anon, authenticated;
grant execute on function public.bg_poll(text, timestamptz) to anon, authenticated;

-- تنبيه فوري لأجهزة المستخدمين (لا يحمل أي محتوى)
create or replace function public._bg_ping(uids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  for t in select token from device_tokens where user_id = any(uids) loop
    begin
      perform realtime.send('{}'::jsonb, 'ping', 'bg-' || t, false);
    exception when others then null;
    end;
  end loop;
exception when others then null;
end $$;
revoke execute on function public._bg_ping(uuid[]) from public, anon, authenticated;

create or replace function public._bg_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type <> 'system' then
    perform _bg_ping(array(select user_id from conversation_members
      where conversation_id = new.conversation_id and user_id is distinct from new.sender_id));
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists bg_on_message on public.messages;
create trigger bg_on_message after insert on public.messages for each row execute function public._bg_on_message();

create or replace function public._bg_on_call() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    perform _bg_ping(array[new.callee]);
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists bg_on_call on public.call_sessions;
create trigger bg_on_call after insert or update of status on public.call_sessions
  for each row execute function public._bg_on_call();

-- =====================================================================
--  الإصدار 9: تشخيص خدمة الخلفية (بدون أي بيانات شخصية)
-- =====================================================================
alter table public.device_tokens add column if not exists info text;
alter table public.device_tokens add column if not exists last_error text;

create table if not exists public.client_logs (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  info text not null check (char_length(info) <= 600)
);
alter table public.client_logs enable row level security;

create or replace function public.bg_report(p_token text, p_info text, p_error text) returns void
language sql security definer set search_path = public as $$
  update device_tokens set info = left(p_info, 300), last_error = left(p_error, 300), last_poll = now()
  where token = p_token;
$$;

create or replace function public.client_log(p_info text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from client_logs where at > now() - interval '1 minute') > 30 then return; end if;
  insert into client_logs(info) values (left(coalesce(p_info, ''), 600));
  delete from client_logs where id < (select max(id) - 300 from client_logs);
end $$;

-- ملخص للمطوّر: حالة الأجهزة بدون هوية أصحابها
create or replace function public.bg_diag() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'devices', (select coalesce(jsonb_agg(jsonb_build_object(
        'dev', left(md5(token), 6), 'created', created_at, 'last_poll', last_poll,
        'info', info, 'error', last_error) order by last_poll desc), '[]'::jsonb)
      from (select * from device_tokens order by last_poll desc limit 30) d),
    'logs', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'info', info) order by id desc), '[]'::jsonb)
      from (select * from client_logs order by id desc limit 40) l),
    'now', now());
$$;

grant execute on function public.bg_report(text, text, text) to anon, authenticated;
grant execute on function public.client_log(text) to anon, authenticated;
grant execute on function public.bg_diag() to anon, authenticated;

-- =====================================================================
--  الإصدار 10: إشعارات Google (Firebase Cloud Messaging)
--  تصل حتى لو كان التطبيق مغلقًا والهاتف يقتل التطبيقات بالخلفية.
--  قاعدة البيانات ترسل الطلب إلى دالة "push" التي توقّع وترسل إلى Google.
-- =====================================================================
do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then raise notice 'pg_net: %', sqlerrm;
end $$;

create table if not exists public.fcm_tokens (
  token text primary key check (char_length(token) between 20 and 4096),
  user_id uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);
create index if not exists fcm_tokens_user_idx on public.fcm_tokens(user_id);
alter table public.fcm_tokens enable row level security;

-- سر مشترك بين قاعدة البيانات ودالة الإرسال (يُنشأ تلقائيًا مرة واحدة)
insert into public.private_settings(key, value)
  values ('push_secret', encode(extensions.gen_random_bytes(24), 'hex'))
  on conflict (key) do nothing;

create or replace function public.register_fcm(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'غير مسموح'; end if;
  insert into fcm_tokens(token, user_id) values (p_token, auth.uid())
    on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
  delete from fcm_tokens where user_id = auth.uid() and token not in (
    select token from fcm_tokens where user_id = auth.uid() order by updated_at desc limit 5);
end $$;

create or replace function public.unregister_fcm(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from fcm_tokens where token = p_token;
$$;

-- هل خدمة إشعارات Google جاهزة على الخادم؟
create or replace function public.push_ready() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from private_settings where key = 'fcm_sa');
$$;

-- المدير يرفع ملف «حساب الخدمة» من لوحة التحكم (يُحفظ سرًا ولا يُقرأ إلا بالسر المشترك)
create or replace function public.admin_set_fcm(p_json text) returns void
language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  begin j := p_json::jsonb; exception when others then raise exception 'الملف غير صالح'; end;
  if j->>'type' <> 'service_account' or j->>'private_key' is null or j->>'client_email' is null then
    raise exception 'هذا ليس ملف حساب خدمة (Service account)';
  end if;
  insert into private_settings(key, value) values ('fcm_sa', j::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

create or replace function public.admin_fcm_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_admin() then null else jsonb_build_object(
    'configured', exists(select 1 from private_settings where key = 'fcm_sa'),
    'project', (select (value::jsonb)->>'project_id' from private_settings where key = 'fcm_sa'),
    'devices', (select count(*) from fcm_tokens)) end;
$$;

-- تستدعيها دالة الإرسال للتحقق من السر وجلب حساب الخدمة
create or replace function public.push_config(p_secret text) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when p_secret is not null and p_secret = (select value from private_settings where key = 'push_secret')
    then (select value::jsonb from private_settings where key = 'fcm_sa') else null end;
$$;

create or replace function public.push_drop_tokens(p_secret text, p_tokens text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_secret is distinct from (select value from private_settings where key = 'push_secret') then return; end if;
  delete from fcm_tokens where token = any(p_tokens);
end $$;

grant execute on function public.register_fcm(text) to authenticated;
grant execute on function public.unregister_fcm(text) to anon, authenticated;
grant execute on function public.push_ready() to anon, authenticated;
grant execute on function public.admin_set_fcm(text) to authenticated;
grant execute on function public.admin_fcm_status() to authenticated;
grant execute on function public.push_config(text) to anon, authenticated;
grant execute on function public.push_drop_tokens(text, text[]) to anon, authenticated;

-- إرسال مجموعة رسائل إلى دالة push (غير متزامن، لا يؤخر حفظ الرسالة)
create or replace function public._push(msgs jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if msgs is null or jsonb_array_length(msgs) = 0 then return; end if;
  if not exists(select 1 from private_settings where key = 'fcm_sa') then return; end if;
  perform net.http_post(
    url := 'https://smjkxsqvdpywumghvnfv.supabase.co/functions/v1/push',
    body := jsonb_build_object('secret', (select value from private_settings where key = 'push_secret'), 'messages', msgs),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 8000);
exception when others then null;
end $$;
revoke execute on function public._push(jsonb) from public, anon, authenticated;

create or replace function public._push_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare cv conversations; sname text; title text; body text; msgs jsonb;
begin
  if new.type = 'system' then return null; end if;
  select * into cv from conversations where id = new.conversation_id;
  select display_name into sname from profiles where id = new.sender_id;
  title := case when cv.type = 'group' then coalesce(cv.name, 'مجموعة') else coalesce(sname, 'رسالة جديدة') end;
  body := case when cv.type = 'group' then coalesce(sname, '') || ': ' else '' end ||
    case when new.type = 'image' then '📷 صورة'
         when new.type = 'video' then '🎬 فيديو'
         when new.type = 'audio' then '🎤 رسالة صوتية'
         when new.type = 'file' then '📎 ' || coalesce(new.file_name, 'ملف')
         else left(coalesce(new.content, ''), 200) end;
  select coalesce(jsonb_agg(jsonb_build_object(
      'token', t.token,
      'notification', jsonb_build_object('title', title, 'body', body),
      'data', jsonb_build_object('kind', 'msg', 'conv', new.conversation_id::text),
      'android', jsonb_build_object('priority', 'high', 'ttl', '86400s',
        'notification', jsonb_build_object('channel_id', 'almajhool_msgs', 'tag', new.conversation_id::text,
          'sound', 'default', 'default_vibrate_timings', true)))), '[]'::jsonb)
    into msgs
  from conversation_members cm
  join fcm_tokens t on t.user_id = cm.user_id
  join profiles p on p.id = cm.user_id
  where cm.conversation_id = new.conversation_id
    and cm.user_id is distinct from new.sender_id
    and not cm.muted and p.notifications_enabled
    and not exists(select 1 from blocks b where b.blocker_id = cm.user_id and b.blocked_id = new.sender_id);
  perform _push(msgs);
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_on_message on public.messages;
create trigger push_on_message after insert on public.messages for each row execute function public._push_on_message();

create or replace function public._push_on_call() returns trigger
language plpgsql security definer set search_path = public as $$
declare msgs jsonb; cname text;
begin
  if tg_op = 'INSERT' then
    select display_name into cname from profiles where id = new.caller;
    select coalesce(jsonb_agg(jsonb_build_object(
        'token', t.token,
        'data', jsonb_build_object('kind', 'call', 'call_id', new.id::text, 'name', coalesce(cname, 'مستخدم'),
          'video', case when new.video then '1' else '0' end),
        'android', jsonb_build_object('priority', 'high', 'ttl', '40s'))), '[]'::jsonb)
      into msgs from fcm_tokens t where t.user_id = new.callee;
  elsif new.status is distinct from old.status and new.status <> 'ringing' then
    select coalesce(jsonb_agg(jsonb_build_object(
        'token', t.token,
        'data', jsonb_build_object('kind', 'call_end', 'call_id', new.id::text),
        'android', jsonb_build_object('priority', 'high', 'ttl', '60s'))), '[]'::jsonb)
      into msgs from fcm_tokens t where t.user_id = new.callee;
  end if;
  perform _push(msgs);
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_on_call on public.call_sessions;
create trigger push_on_call after insert or update of status on public.call_sessions
  for each row execute function public._push_on_call();

-- تشخيص للمطوّر (بدون أسرار)
create or replace function public.push_diag() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  return jsonb_build_object(
    'ready', exists(select 1 from private_settings where key = 'fcm_sa'),
    'tokens', (select count(*) from fcm_tokens),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('status', status_code, 'body', left(content, 200), 'at', created)), '[]'::jsonb)
               from (select * from net._http_response order by id desc limit 8) r));
end $$;
grant execute on function public.push_diag() to anon, authenticated;

-- =====================================================================
--  الإصدار 11: إرسال إشعارات Google مباشرة من قاعدة البيانات
--  GitHub Actions يجدد مفتاح Google كل 10 دقائق (يتحقق الخادم من هوية GitHub)،
--  وقاعدة البيانات ترسل إلى Google مباشرة — بدون دوال خارجية.
-- =====================================================================

-- التحقق أن الطلب قادم من GitHub Actions لهذا المستودع فقط
create or replace function public._gh_verify(p_token text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare r extensions.http_response; j jsonb;
begin
  if p_token is null or char_length(p_token) < 20 then return false; end if;
  select * into r from extensions.http((
    'GET', 'https://api.github.com/installation/repositories',
    array[extensions.http_header('Authorization', 'Bearer ' || p_token),
          extensions.http_header('User-Agent', 'almajhool-db'),
          extensions.http_header('Accept', 'application/vnd.github+json')],
    null, null)::extensions.http_request);
  if r.status <> 200 then return false; end if;
  j := r.content::jsonb;
  return (j->>'total_count')::int = 1
     and j->'repositories'->0->>'full_name' = 'almajhool-dev/almajhool-ap';
exception when others then return false;
end $$;
revoke execute on function public._gh_verify(text) from public, anon, authenticated;

create or replace function public.push_refresh_config(p_gh text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _gh_verify(p_gh) then return null; end if;
  return coalesce((select value::jsonb from private_settings where key = 'fcm_sa'), '{"verified": true}'::jsonb);
end $$;

create or replace function public.push_set_access(p_gh text, p_access text, p_expires int) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not _gh_verify(p_gh) then return false; end if;
  insert into private_settings(key, value) values ('fcm_access', p_access)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into private_settings(key, value)
    values ('fcm_access_exp', (extract(epoch from now())::bigint + coalesce(p_expires, 3600))::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return true;
end $$;
grant execute on function public.push_refresh_config(text) to anon, authenticated;
grant execute on function public.push_set_access(text, text, int) to anon, authenticated;

create or replace function public.push_ready() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from private_settings where key = 'fcm_sa')
     and coalesce((select value::bigint from private_settings where key = 'fcm_access_exp'), 0)
         > extract(epoch from now())::bigint + 120;
$$;

-- إرسال مباشر إلى Google
create or replace function public._push(msgs jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare m jsonb; tok text; pid text;
begin
  if msgs is null or jsonb_array_length(msgs) = 0 or not push_ready() then return; end if;
  select value into tok from private_settings where key = 'fcm_access';
  select (value::jsonb)->>'project_id' into pid from private_settings where key = 'fcm_sa';
  for m in select * from jsonb_array_elements(msgs) loop
    perform net.http_post(
      url := 'https://fcm.googleapis.com/v1/projects/' || pid || '/messages:send',
      body := jsonb_build_object('message', m),
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || tok),
      timeout_milliseconds := 8000);
  end loop;
exception when others then null;
end $$;
revoke execute on function public._push(jsonb) from public, anon, authenticated;

-- تنظيف الأجهزة التي لم تعد مسجلة لدى Google (يعمل كل ساعة)
create or replace function public._push_cleanup() returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from fcm_tokens where updated_at < now() - interval '60 days';
exception when others then null;
end $$;

create or replace function public.push_diag() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  return jsonb_build_object(
    'sa', exists(select 1 from private_settings where key = 'fcm_sa'),
    'ready', push_ready(),
    'access_left_min', (coalesce((select value::bigint from private_settings where key = 'fcm_access_exp'), 0)
                        - extract(epoch from now())::bigint) / 60,
    'tokens', (select count(*) from fcm_tokens),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('status', status_code, 'body', left(content, 160), 'at', created)), '[]'::jsonb)
               from (select * from net._http_response order by id desc limit 8) r));
end $$;
grant execute on function public.push_diag() to anon, authenticated;

-- =====================================================================
--  الإصدار 12: تقديم ملف حساب الخدمة بأمان بدون لوحة التحكم
--  الملف يُحفظ «معلّقًا»، ولا يُفعّل إلا بعد أن يثبت GitHub Actions أن Google تقبله فعلًا
--  (أي لا يمكن تفعيله إلا بملف حقيقي صادر من مشروع almajhool-aefc9).
-- =====================================================================
create or replace function public.push_submit_sa(p_json text) returns text
language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  if char_length(coalesce(p_json, '')) > 6000 then return 'too large'; end if;
  begin j := p_json::jsonb; exception when others then return 'invalid json'; end;
  if j->>'type' <> 'service_account' or j->>'project_id' <> 'almajhool-aefc9'
     or j->>'private_key' is null or j->>'client_email' not like '%@almajhool-aefc9.iam.gserviceaccount.com' then
    return 'rejected';
  end if;
  insert into private_settings(key, value) values ('fcm_sa_pending', j::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return 'pending';
end $$;
grant execute on function public.push_submit_sa(text) to anon, authenticated;

create or replace function public.push_refresh_config(p_gh text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _gh_verify(p_gh) then return null; end if;
  return jsonb_build_object('verified', true,
    'sa', (select value::jsonb from private_settings where key = 'fcm_sa'),
    'pending', (select value::jsonb from private_settings where key = 'fcm_sa_pending'));
end $$;

create or replace function public.push_promote(p_gh text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if not _gh_verify(p_gh) then return false; end if;
  select value into v from private_settings where key = 'fcm_sa_pending';
  if v is null then return false; end if;
  insert into private_settings(key, value) values ('fcm_sa', v)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  delete from private_settings where key = 'fcm_sa_pending';
  return true;
end $$;
grant execute on function public.push_promote(text) to anon, authenticated;

-- =====================================================================
--  الإصدار 13: الأصدقاء والمتابعة، خصوصية المنشورات وألوانها، القصص،
--  إيقاف النسخ القديمة، والرد من الإشعارات
-- =====================================================================

-- ---------- الأصدقاء ----------
create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from contact_requests
    where status = 'accepted'
      and least(sender_id, receiver_id) = least(a, b)
      and greatest(sender_id, receiver_id) = greatest(a, b));
$$;

-- ---------- المتابعة ----------
create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows(followee_id);
alter table public.follows enable row level security;
drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows for select to authenticated using (true);
drop policy if exists follows_insert on public.follows;
create policy follows_insert on public.follows for insert to authenticated
  with check (follower_id = auth.uid() and not is_banned() and not is_blocked_between(follower_id, followee_id));
drop policy if exists follows_delete on public.follows;
create policy follows_delete on public.follows for delete to authenticated using (follower_id = auth.uid());

create or replace function public.on_follow() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  select display_name into n from profiles where id = new.follower_id;
  perform add_capped_xp(new.followee_id, 'follow_xp', 3, 30);
  perform notify_user(new.followee_id, 'follow', 'متابع جديد',
    coalesce(n, '') || ' بدأ بمتابعتك', jsonb_build_object('user_id', new.follower_id));
  return new;
exception when others then return new;
end $$;
drop trigger if exists trg_on_follow on public.follows;
create trigger trg_on_follow after insert on public.follows for each row execute function public.on_follow();

create or replace function public.profile_counts(uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'friends', (select count(*) from contact_requests where status = 'accepted' and (sender_id = uid or receiver_id = uid)),
    'followers', (select count(*) from follows where followee_id = uid),
    'following', (select count(*) from follows where follower_id = uid),
    'posts', (select count(*) from posts where author_id = uid and not deleted),
    'i_follow', exists(select 1 from follows where follower_id = auth.uid() and followee_id = uid));
$$;

-- ---------- المنشورات: ألوان وخصوصية ----------
alter table public.posts add column if not exists text_color bigint;
alter table public.posts add column if not exists bg_color bigint;
alter table public.posts add column if not exists visibility text not null default 'public';
do $$ begin
  alter table public.posts add constraint posts_visibility_chk check (visibility in ('public','friends','private','custom'));
exception when others then null; end $$;

create table if not exists public.post_audience (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (post_id, user_id)
);
alter table public.post_audience enable row level security;
drop policy if exists post_audience_select on public.post_audience;
create policy post_audience_select on public.post_audience for select to authenticated
  using (user_id = auth.uid() or exists(select 1 from posts p where p.id = post_id and p.author_id = auth.uid()));

create or replace function public.can_see_post(pid uuid, author uuid, vis text) returns boolean
language sql stable security definer set search_path = public as $$
  select author = auth.uid()
      or vis = 'public'
      or (vis = 'friends' and are_friends(auth.uid(), author))
      or (vis = 'custom' and exists(select 1 from post_audience a where a.post_id = pid and a.user_id = auth.uid()));
$$;

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select to authenticated
  using (is_admin() or (not deleted and not is_blocked_between(auth.uid(), author_id)
                        and can_see_post(id, author_id, visibility)));

create or replace function public.save_post(pid uuid, p_content text, p_image text, p_text_color bigint,
  p_bg_color bigint, p_visibility text, p_audience uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if not can_post() then raise exception 'لا يمكنك النشر الآن'; end if;
  if char_length(coalesce(p_content, '')) > 3000 then raise exception 'النص طويل جدًا'; end if;
  if char_length(coalesce(trim(p_content), '')) = 0 and p_image is null then raise exception 'المنشور فارغ'; end if;
  if p_visibility not in ('public','friends','private','custom') then p_visibility := 'public'; end if;
  if pid is null then
    insert into posts(author_id, content, image_url, text_color, bg_color, visibility)
      values (auth.uid(), coalesce(trim(p_content), ''), p_image, p_text_color, p_bg_color, p_visibility)
      returning id into rid;
  else
    update posts set content = coalesce(trim(p_content), ''), image_url = p_image, text_color = p_text_color,
      bg_color = p_bg_color, visibility = p_visibility, edited_at = now()
    where id = pid and author_id = auth.uid() and not deleted returning id into rid;
    if rid is null then raise exception 'لا يمكن تعديل هذا المنشور'; end if;
    delete from post_audience where post_id = rid;
  end if;
  if p_visibility = 'custom' and p_audience is not null then
    insert into post_audience(post_id, user_id)
      select rid, u from unnest(p_audience) u where u <> auth.uid() on conflict do nothing;
  end if;
  return rid;
end $$;
grant execute on function public.save_post(uuid, text, text, bigint, bigint, text, uuid[]) to authenticated;

-- ---------- القصص (24 ساعة) ----------
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'image' check (kind in ('image','text')),
  media_url text,
  content text check (content is null or char_length(content) <= 500),
  bg_color bigint,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);
create index if not exists stories_active_idx on public.stories(expires_at desc, user_id);
alter table public.stories enable row level security;
drop policy if exists stories_select on public.stories;
create policy stories_select on public.stories for select to authenticated
  using (user_id = auth.uid() or is_admin()
         or (expires_at > now() and not is_blocked_between(auth.uid(), user_id)));
drop policy if exists stories_insert on public.stories;
create policy stories_insert on public.stories for insert to authenticated
  with check (user_id = auth.uid() and can_post());
drop policy if exists stories_delete on public.stories;
create policy stories_delete on public.stories for delete to authenticated using (user_id = auth.uid() or is_admin());

create or replace function public.before_story_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from stories where user_id = new.user_id and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limited: قصص كثيرة، انتظر قليلًا';
  end if;
  new.created_at := now(); new.expires_at := now() + interval '24 hours';
  return new;
end $$;
drop trigger if exists trg_before_story on public.stories;
create trigger trg_before_story before insert on public.stories for each row execute function public.before_story_insert();

create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);
alter table public.story_views enable row level security;
drop policy if exists story_views_select on public.story_views;
create policy story_views_select on public.story_views for select to authenticated
  using (viewer_id = auth.uid() or exists(select 1 from stories s where s.id = story_id and s.user_id = auth.uid()));
drop policy if exists story_views_insert on public.story_views;
create policy story_views_insert on public.story_views for insert to authenticated with check (viewer_id = auth.uid());

-- ---------- إيقاف النسخ القديمة ----------
alter table public.app_settings add column if not exists service_enabled boolean not null default true;
alter table public.app_settings add column if not exists old_blocked boolean not null default false;
alter table public.app_settings add column if not exists min_build int not null default 0;
alter table public.app_settings add column if not exists update_url text not null default 'https://t.me/ikd5n';
alter table public.app_settings add column if not exists update_message text not null
  default 'هذه النسخة قديمة ومتوقفة. نزّل النسخة الجديدة من قناتنا على تلكرام.';

create or replace function public.can_post() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and not is_banned()
     and ((select service_enabled from app_settings where id = 1) or is_admin());
$$;

create or replace function public.admin_set_app(enabled boolean, message text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  update app_settings set service_enabled = enabled,
    app_enabled = enabled and not old_blocked,
    maintenance_message = case when old_blocked then maintenance_message
      else coalesce(nullif(trim(message), ''), maintenance_message) end,
    updated_at = now()
  where id = 1;
end $$;

-- block=true: كل نسخة أقدم من p_build تتوقف وتظهر لها رسالة التحديث مع رابط تلكرام
create or replace function public.admin_block_old(p_build int, p_block boolean, p_message text, p_url text)
returns void language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  msg := coalesce(nullif(trim(p_message), ''), (select update_message from app_settings where id = 1));
  update app_settings set
    old_blocked = p_block,
    min_build = case when p_block then greatest(coalesce(p_build, 0), 0) else 0 end,
    update_message = msg,
    update_url = coalesce(nullif(trim(p_url), ''), update_url),
    app_enabled = service_enabled and not p_block,
    maintenance_message = case when p_block
      then msg || E'\n' || coalesce(nullif(trim(p_url), ''), update_url) else maintenance_message end,
    updated_at = now()
  where id = 1;
end $$;
grant execute on function public.admin_block_old(int, boolean, text, text) to authenticated;

-- ---------- الرد من الإشعار (التطبيق مغلق: نستخدم رمز الجهاز بدل تسجيل الدخول) ----------
create or replace function public._device_user(p_token text) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select user_id from fcm_tokens where token = p_token),
    (select user_id from device_tokens where token = p_token));
$$;
revoke execute on function public._device_user(text) from public, anon, authenticated;

create or replace function public.device_reply(p_token text, p_conv uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _device_user(p_token);
begin
  if uid is null or char_length(coalesce(trim(p_text), '')) = 0 then raise exception 'غير مسموح'; end if;
  if not exists(select 1 from conversation_members where conversation_id = p_conv and user_id = uid) then
    raise exception 'غير مسموح';
  end if;
  if exists(select 1 from profiles where id = uid and is_banned) then raise exception 'غير مسموح'; end if;
  if (select type from conversations where id = p_conv) = 'direct' and exists(
       select 1 from conversation_members m where m.conversation_id = p_conv and m.user_id <> uid
         and is_blocked_between(uid, m.user_id)) then
    raise exception 'غير مسموح';
  end if;
  insert into messages(conversation_id, sender_id, type, content, client_id)
    values (p_conv, uid, 'text', left(trim(p_text), 4000), 'n-' || gen_random_uuid()::text);
end $$;

create or replace function public.device_call_action(p_token text, p_call uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _device_user(p_token);
begin
  if uid is null or p_status not in ('rejected', 'busy') then raise exception 'غير مسموح'; end if;
  update call_sessions set status = p_status, updated_at = now()
    where id = p_call and callee = uid and status = 'ringing';
end $$;
grant execute on function public.device_reply(text, uuid, text) to anon, authenticated;
grant execute on function public.device_call_action(text, uuid, text) to anon, authenticated;

-- رقم نسخة التطبيق لكل جهاز (النسخ الجديدة تعرض الإشعار بنفسها مع زر «رد»)
alter table public.fcm_tokens add column if not exists app_build int not null default 0;
create or replace function public.register_fcm2(p_token text, p_build int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform register_fcm(p_token);
  update fcm_tokens set app_build = coalesce(p_build, 0) where token = p_token;
end $$;
grant execute on function public.register_fcm2(text, int) to authenticated;

-- الرسائل: نرسلها كبيانات حتى يعرضها التطبيق بإشعار فيه زر «رد»
create or replace function public._push_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare cv conversations; sname text; title text; body text; msgs jsonb;
begin
  if new.type = 'system' then return null; end if;
  select * into cv from conversations where id = new.conversation_id;
  select display_name into sname from profiles where id = new.sender_id;
  title := case when cv.type = 'group' then coalesce(cv.name, 'مجموعة') else coalesce(sname, 'رسالة جديدة') end;
  body := case when cv.type = 'group' then coalesce(sname, '') || ': ' else '' end ||
    case when new.type = 'image' then '📷 صورة'
         when new.type = 'video' then '🎬 فيديو'
         when new.type = 'audio' then '🎤 رسالة صوتية'
         when new.type = 'file' then '📎 ' || coalesce(new.file_name, 'ملف')
         else left(coalesce(new.content, ''), 300) end;
  select coalesce(jsonb_agg(jsonb_build_object(
      'token', t.token,
      'data', jsonb_build_object('kind', 'msg', 'conv', new.conversation_id::text, 'title', title, 'body', body),
      'android', jsonb_build_object('priority', 'high', 'ttl', '86400s'))
      -- النسخ القديمة (قبل 35) لا تعرض إشعار البيانات، فنرسل لها إشعارًا جاهزًا
      || case when t.app_build >= 35 then '{}'::jsonb else jsonb_build_object(
        'notification', jsonb_build_object('title', title, 'body', body),
        'android', jsonb_build_object('priority', 'high', 'ttl', '86400s',
          'notification', jsonb_build_object('channel_id', 'almajhool_msgs', 'tag', new.conversation_id::text,
            'sound', 'default'))) end), '[]'::jsonb)
    into msgs
  from conversation_members cm
  join fcm_tokens t on t.user_id = cm.user_id
  join profiles p on p.id = cm.user_id
  where cm.conversation_id = new.conversation_id
    and cm.user_id is distinct from new.sender_id
    and not cm.muted and p.notifications_enabled
    and not exists(select 1 from blocks b where b.blocker_id = cm.user_id and b.blocked_id = new.sender_id);
  perform _push(msgs);
  return null;
exception when others then return null;
end $$;

-- =====================================================================
--  الإصدار 14: البث المباشر (لايف) مثل تيك توك
--  الفيديو عبر LiveKit (يتكيف حسب نت كل مشاهد)، والتعليقات والتكبيس والإدارة هنا.
-- =====================================================================

create table if not exists public.lives (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default '' check (char_length(title) <= 120),
  status text not null default 'live' check (status in ('live', 'ended')),
  viewer_count int not null default 0,
  peak_viewers int not null default 0,
  like_count bigint not null default 0,
  started_at timestamptz not null default now(),
  last_beat timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text
);
create index if not exists lives_active_idx on public.lives(status, last_beat desc);
alter table public.lives enable row level security;
drop policy if exists lives_select on public.lives;
create policy lives_select on public.lives for select to authenticated
  using (is_admin() or host_id = auth.uid() or not is_blocked_between(auth.uid(), host_id));

create table if not exists public.live_comments (
  id bigint generated always as identity primary key,
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'join', 'system')),
  content text not null check (char_length(content) between 1 and 300),
  created_at timestamptz not null default now()
);
create index if not exists live_comments_live_idx on public.live_comments(live_id, id desc);
alter table public.live_comments enable row level security;
drop policy if exists live_comments_select on public.live_comments;
create policy live_comments_select on public.live_comments for select to authenticated using (true);

create table if not exists public.live_mods (
  host_id uuid not null references public.profiles(id) on delete cascade,
  mod_id uuid not null references public.profiles(id) on delete cascade,
  primary key (host_id, mod_id)
);
create table if not exists public.live_mutes (
  host_id uuid not null references public.profiles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  until timestamptz, -- null = للأبد
  primary key (host_id, user_id)
);
create table if not exists public.live_bans (
  host_id uuid not null references public.profiles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (host_id, user_id)
);
create table if not exists public.live_reports (
  live_id uuid not null references public.lives(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null default '',
  created_at timestamptz not null default now(),
  primary key (live_id, reporter_id)
);
create table if not exists public.live_penalties (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  strikes int not null default 0,
  banned_until timestamptz,
  permanent boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.live_mods enable row level security;
alter table public.live_mutes enable row level security;
alter table public.live_bans enable row level security;
alter table public.live_reports enable row level security;
alter table public.live_penalties enable row level security;
drop policy if exists live_mods_select on public.live_mods;
create policy live_mods_select on public.live_mods for select to authenticated using (true);

do $$ begin
  begin execute 'alter publication supabase_realtime add table public.live_comments'; exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table public.lives'; exception when others then null; end;
end $$;

-- ---------- رموز الدخول لـ LiveKit (JWT موقّعة داخل قاعدة البيانات) ----------
create or replace function public._b64url(b bytea) returns text
language sql immutable as $$ select translate(encode(b, 'base64'), E'+/\n=', '-_'); $$;

create or replace function public._lk_token(p_identity text, p_name text, p_room text, p_publish boolean,
  p_admin boolean default false, p_ttl int default 21600) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare k text; sec text; head text; body text; now_s bigint := extract(epoch from now())::bigint; grant_ jsonb;
begin
  select value into k from private_settings where key = 'livekit_key';
  select value into sec from private_settings where key = 'livekit_secret';
  if k is null or sec is null then raise exception 'البث المباشر غير مفعّل بعد'; end if;
  grant_ := case when p_admin
    then jsonb_build_object('room', p_room, 'roomAdmin', true, 'roomCreate', true, 'roomList', true)
    else jsonb_build_object('room', p_room, 'roomJoin', true, 'canPublish', p_publish, 'canSubscribe', true,
                            'canPublishData', true, 'canUpdateOwnMetadata', true) end;
  head := _b64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'));
  body := _b64url(convert_to(jsonb_build_object('iss', k, 'sub', p_identity, 'name', coalesce(p_name, ''),
            'nbf', now_s - 10, 'exp', now_s + p_ttl, 'video', grant_)::text, 'utf8'));
  return head || '.' || body || '.' || _b64url(extensions.hmac(head || '.' || body, sec, 'sha256'));
end $$;
revoke execute on function public._lk_token(text, text, text, boolean, boolean, int) from public, anon, authenticated;

create or replace function public._lk_url() returns text
language sql stable security definer set search_path = public as $$
  select value from private_settings where key = 'livekit_url';
$$;

-- استدعاء واجهة LiveKit (طرد مشاهد / إغلاق غرفة) — غير متزامن
create or replace function public._lk_api(p_method text, p_room text, p_body jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u text := _lk_url();
begin
  if u is null then return; end if;
  u := replace(replace(u, 'wss://', 'https://'), 'ws://', 'http://');
  perform net.http_post(
    url := rtrim(u, '/') || '/twirp/livekit.RoomService/' || p_method,
    body := p_body,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _lk_token('server', 'server', p_room, false, true, 300)),
    timeout_milliseconds := 8000);
exception when others then null;
end $$;
revoke execute on function public._lk_api(text, text, jsonb) from public, anon, authenticated;

create or replace function public.admin_set_live(p_url text, p_key text, p_secret text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  if coalesce(p_url, '') not like 'wss://%' or char_length(coalesce(p_key, '')) < 5 or char_length(coalesce(p_secret, '')) < 10 then
    raise exception 'بيانات غير صالحة: تأكد من URL (يبدأ بـ wss://) و API Key و API Secret';
  end if;
  insert into private_settings(key, value) values ('livekit_url', trim(p_url)), ('livekit_key', trim(p_key)),
    ('livekit_secret', trim(p_secret))
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

create or replace function public.live_ready() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from private_settings where key = 'livekit_secret');
$$;

-- ---------- العقوبات ----------
create or replace function public._live_ban_message(uid uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare p live_penalties;
begin
  select * into p from live_penalties where user_id = uid;
  if p.user_id is null then return null; end if;
  if p.permanent then return 'تم حظرك من البث المباشر نهائيًا. راسل إدارة التطبيق.'; end if;
  if p.banned_until is not null and p.banned_until > now() then
    return 'لا يمكنك البث الآن بسبب مخالفة. يُفتح البث بعد ' ||
      greatest(1, ceil(extract(epoch from (p.banned_until - now())) / 60))::int || ' دقيقة.';
  end if;
  return null;
end $$;

create or replace function public._live_close(p_live uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update lives set status = 'ended', ended_at = now(), ended_reason = p_reason where id = p_live and status = 'live';
  perform _lk_api('DeleteRoom', p_live::text, jsonb_build_object('room', p_live::text));
end $$;

-- ---------- البث ----------
create or replace function public.live_start(p_title text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare msg text; lid uuid; me profiles; msgs jsonb;
begin
  if auth.uid() is null or not can_post() then raise exception 'لا يمكنك البث الآن'; end if;
  if not live_ready() then raise exception 'البث المباشر غير مفعّل بعد من الإدارة'; end if;
  msg := _live_ban_message(auth.uid());
  if msg is not null then raise exception '%', msg; end if;
  update lives set status = 'ended', ended_at = now(), ended_reason = 'new'
    where host_id = auth.uid() and status = 'live';
  select * into me from profiles where id = auth.uid();
  insert into lives(host_id, title) values (auth.uid(), left(coalesce(trim(p_title), ''), 120)) returning id into lid;

  -- إشعار للأصدقاء والمتابعين
  insert into notifications(user_id, type, title, body, data)
    select distinct u, 'live', '🔴 بث مباشر', me.display_name || ' بدأ بثًا مباشرًا الآن', jsonb_build_object('live_id', lid)
    from (
      select follower_id u from follows where followee_id = auth.uid()
      union select case when sender_id = auth.uid() then receiver_id else sender_id end
        from contact_requests where status = 'accepted' and (sender_id = auth.uid() or receiver_id = auth.uid())
    ) x limit 1000;
  select coalesce(jsonb_agg(jsonb_build_object(
      'token', t.token,
      'notification', jsonb_build_object('title', '🔴 ' || me.display_name || ' في بث مباشر', 'body', coalesce(nullif(p_title, ''), 'انضم الآن!')),
      'data', jsonb_build_object('kind', 'live', 'live_id', lid::text),
      'android', jsonb_build_object('priority', 'high', 'ttl', '1800s',
        'notification', jsonb_build_object('channel_id', 'almajhool_msgs', 'tag', 'live-' || auth.uid()::text)))), '[]'::jsonb)
    into msgs
  from fcm_tokens t
  where t.user_id in (
    select follower_id from follows where followee_id = auth.uid()
    union select case when sender_id = auth.uid() then receiver_id else sender_id end
      from contact_requests where status = 'accepted' and (sender_id = auth.uid() or receiver_id = auth.uid()));
  perform _push(msgs);

  return jsonb_build_object('live_id', lid, 'url', _lk_url(),
    'token', _lk_token(auth.uid()::text, me.display_name, lid::text, true));
end $$;

create or replace function public.live_join(p_live uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l lives; me profiles;
begin
  select * into l from lives where id = p_live;
  if l.id is null or l.status <> 'live' then raise exception 'انتهى هذا البث'; end if;
  if is_banned() then raise exception 'حسابك محظور'; end if;
  if exists(select 1 from live_bans where host_id = l.host_id and user_id = auth.uid()) then
    raise exception 'تم طردك من بثوث هذا المستخدم';
  end if;
  if is_blocked_between(auth.uid(), l.host_id) then raise exception 'لا يمكنك مشاهدة هذا البث'; end if;
  select * into me from profiles where id = auth.uid();
  if l.host_id <> auth.uid() then
    insert into live_comments(live_id, user_id, kind, content) values (p_live, auth.uid(), 'join', 'انضم');
  end if;
  return jsonb_build_object('url', _lk_url(),
    'token', _lk_token(auth.uid()::text, me.display_name, p_live::text, l.host_id = auth.uid()),
    'host_id', l.host_id, 'title', l.title, 'like_count', l.like_count, 'cover_url', l.cover_url,
    'share_count', l.share_count,
    'is_mod', exists(select 1 from live_mods where host_id = l.host_id and mod_id = auth.uid()));
end $$;

create or replace function public.live_heartbeat(p_live uuid, p_viewers int, p_likes bigint) returns text
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  update lives set last_beat = now(), viewer_count = greatest(coalesce(p_viewers, 0), 0),
    peak_viewers = greatest(peak_viewers, coalesce(p_viewers, 0)),
    like_count = greatest(like_count, coalesce(p_likes, 0))
  where id = p_live and host_id = auth.uid() returning status into st;
  return coalesce(st, 'ended');
end $$;

create or replace function public.live_end(p_live uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from lives where id = p_live and (host_id = auth.uid() or is_admin())) then
    raise exception 'غير مسموح';
  end if;
  perform _live_close(p_live, 'host');
end $$;

create or replace function public.live_comment(p_live uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare l lives; m live_mutes;
begin
  select * into l from lives where id = p_live;
  if l.id is null or l.status <> 'live' then raise exception 'انتهى البث'; end if;
  if is_banned() or exists(select 1 from live_bans where host_id = l.host_id and user_id = auth.uid()) then
    raise exception 'غير مسموح';
  end if;
  select * into m from live_mutes where host_id = l.host_id and user_id = auth.uid();
  if m.user_id is not null and (m.until is null or m.until > now()) then
    raise exception '%', case when m.until is null then 'أنت مكتوم في بثوث هذا المستخدم'
      else 'أنت مكتوم لمدة ' || greatest(1, ceil(extract(epoch from (m.until - now())) / 60))::int || ' دقيقة' end;
  end if;
  if (select count(*) from live_comments where user_id = auth.uid() and created_at > now() - interval '10 seconds') >= 5 then
    raise exception 'rate_limited: تمهّل قليلًا';
  end if;
  insert into live_comments(live_id, user_id, content) values (p_live, auth.uid(), left(trim(p_text), 300));
end $$;

-- إجراءات الإدارة داخل البث: mute5 | mute | unmute | kick | mod | unmod
create or replace function public.live_mod_action(p_live uuid, p_target uuid, p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare l lives; is_host boolean; is_mod boolean; n text;
begin
  select * into l from lives where id = p_live;
  if l.id is null then raise exception 'البث غير موجود'; end if;
  is_host := l.host_id = auth.uid();
  is_mod := exists(select 1 from live_mods where host_id = l.host_id and mod_id = auth.uid());
  if not (is_host or is_mod or is_admin()) then raise exception 'غير مسموح'; end if;
  if p_target = l.host_id then raise exception 'لا يمكن تطبيق هذا على صاحب البث'; end if;
  if p_action in ('mod', 'unmod') and not (is_host or is_admin()) then raise exception 'صاحب البث فقط يعيّن المشرفين'; end if;
  if not (is_host or is_admin()) and exists(select 1 from live_mods where host_id = l.host_id and mod_id = p_target) then
    raise exception 'لا يمكن للمشرف معاقبة مشرف آخر';
  end if;
  select display_name into n from profiles where id = p_target;
  if p_action = 'mute5' then
    insert into live_mutes(host_id, user_id, until) values (l.host_id, p_target, now() + interval '5 minutes')
      on conflict (host_id, user_id) do update set until = excluded.until;
    insert into live_comments(live_id, user_id, kind, content) values (p_live, p_target, 'system', 'تم كتم ' || n || ' لمدة 5 دقائق');
  elsif p_action = 'mute' then
    insert into live_mutes(host_id, user_id, until) values (l.host_id, p_target, null)
      on conflict (host_id, user_id) do update set until = null;
    insert into live_comments(live_id, user_id, kind, content) values (p_live, p_target, 'system', 'تم كتم ' || n || ' للأبد');
  elsif p_action = 'unmute' then
    delete from live_mutes where host_id = l.host_id and user_id = p_target;
  elsif p_action = 'kick' then
    insert into live_bans(host_id, user_id) values (l.host_id, p_target) on conflict do nothing;
    insert into live_comments(live_id, user_id, kind, content) values (p_live, p_target, 'system', 'تم طرد ' || n || ' من البث');
    perform _lk_api('RemoveParticipant', p_live::text, jsonb_build_object('room', p_live::text, 'identity', p_target::text));
  elsif p_action = 'unban' then
    delete from live_bans where host_id = l.host_id and user_id = p_target;
  elsif p_action = 'mod' then
    insert into live_mods(host_id, mod_id) values (l.host_id, p_target) on conflict do nothing;
    insert into live_comments(live_id, user_id, kind, content) values (p_live, p_target, 'system', n || ' أصبح مشرفًا');
  elsif p_action = 'unmod' then
    delete from live_mods where host_id = l.host_id and mod_id = p_target;
  else
    raise exception 'إجراء غير معروف';
  end if;
end $$;

create or replace function public.live_report(p_live uuid, p_reason text) returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  insert into live_reports(live_id, reporter_id, reason) values (p_live, auth.uid(), left(coalesce(p_reason, ''), 300))
    on conflict (live_id, reporter_id) do update set reason = excluded.reason, created_at = now();
  select count(*) into c from live_reports where live_id = p_live;
  return c;
end $$;

-- المدير: البث مخالف ← إغلاقه + عقوبة متصاعدة (تحذير، 10 دقائق، ساعة، حظر مؤبد)
create or replace function public.admin_live_violation(p_live uuid) returns text
language plpgsql security definer set search_path = public as $$
declare l lives; s int; result text;
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  select * into l from lives where id = p_live;
  if l.id is null then raise exception 'البث غير موجود'; end if;
  perform _live_close(p_live, 'violation');
  insert into live_penalties(user_id, strikes) values (l.host_id, 1)
    on conflict (user_id) do update set strikes = live_penalties.strikes + 1, updated_at = now()
    returning strikes into s;
  if s = 1 then
    result := 'تحذير أول';
    perform notify_user(l.host_id, 'live_penalty', '⚠️ تحذير أول', 'تم إغلاق بثك بسبب مخالفة القواعد. المخالفة القادمة توقفك 10 دقائق.', '{}'::jsonb);
  elsif s = 2 then
    update live_penalties set banned_until = now() + interval '10 minutes' where user_id = l.host_id;
    result := 'إيقاف 10 دقائق';
    perform notify_user(l.host_id, 'live_penalty', '⛔ إيقاف البث 10 دقائق', 'مخالفة ثانية: لا يمكنك البث لمدة 10 دقائق.', '{}'::jsonb);
  elsif s = 3 then
    update live_penalties set banned_until = now() + interval '1 hour' where user_id = l.host_id;
    result := 'إيقاف ساعة';
    perform notify_user(l.host_id, 'live_penalty', '⛔ إيقاف البث ساعة', 'مخالفة ثالثة: لا يمكنك البث لمدة ساعة. المخالفة القادمة حظر نهائي.', '{}'::jsonb);
  else
    update live_penalties set permanent = true where user_id = l.host_id;
    result := 'حظر مؤبد من البث';
    perform notify_user(l.host_id, 'live_penalty', '🚫 حظر نهائي من البث', 'تم حظرك من البث المباشر نهائيًا بسبب تكرار المخالفات.', '{}'::jsonb);
  end if;
  return result;
end $$;

create or replace function public.admin_live_unban(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للمدير فقط'; end if;
  update live_penalties set strikes = 0, banned_until = null, permanent = false, updated_at = now() where user_id = p_user;
end $$;

create or replace function public.admin_lives() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_admin() then '[]'::jsonb else coalesce((
    select jsonb_agg(x order by (x->>'reports')::int desc, x->>'started_at' desc) from (
      select jsonb_build_object('id', l.id, 'title', l.title, 'host_id', l.host_id, 'host', p.display_name,
        'status', case when l.status = 'live' and l.last_beat > now() - interval '60 seconds' then 'live' else 'ended' end,
        'viewers', l.viewer_count, 'likes', l.like_count, 'started_at', l.started_at,
        'reports', (select count(*) from live_reports r where r.live_id = l.id),
        'reasons', (select coalesce(jsonb_agg(r.reason) filter (where r.reason <> ''), '[]'::jsonb)
                    from (select reason from live_reports r where r.live_id = l.id order by created_at desc limit 5) r),
        'strikes', coalesce((select strikes from live_penalties where user_id = l.host_id), 0)) x
      from lives l join profiles p on p.id = l.host_id
      where l.started_at > now() - interval '2 days'
        and (l.status = 'live' or exists(select 1 from live_reports r where r.live_id = l.id))
      limit 100) t), '[]'::jsonb) end;
$$;

create or replace function public.admin_live_penalties() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_admin() then '[]'::jsonb else coalesce(jsonb_agg(jsonb_build_object(
    'user_id', lp.user_id, 'name', p.display_name, 'strikes', lp.strikes, 'banned_until', lp.banned_until,
    'permanent', lp.permanent) order by lp.updated_at desc), '[]'::jsonb) end
  from live_penalties lp join profiles p on p.id = lp.user_id where lp.strikes > 0 or lp.permanent;
$$;

-- البثوث النشطة مرتبة: التكبيس والمشاهدين يرفعون البث للأعلى
create or replace function public.active_lives() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'score')::numeric desc), '[]'::jsonb) from (
    select jsonb_build_object('id', l.id, 'title', l.title, 'host_id', l.host_id, 'viewers', l.viewer_count,
      'likes', l.like_count, 'started_at', l.started_at,
      'score', l.viewer_count * 10 + l.like_count / 20.0
        + case when exists(select 1 from follows f where f.follower_id = auth.uid() and f.followee_id = l.host_id) then 500 else 0 end,
      'host', jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name,
        'avatar_url', p.avatar_url, 'is_verified', p.is_verified, 'is_owner', p.is_owner, 'xp', p.xp)) x
    from lives l join profiles p on p.id = l.host_id
    where l.status = 'live' and l.last_beat > now() - interval '60 seconds'
      and not is_blocked_between(auth.uid(), l.host_id)
    limit 100) t;
$$;

grant execute on function public.admin_set_live(text, text, text) to authenticated;
grant execute on function public.live_ready() to authenticated;
grant execute on function public.live_start(text) to authenticated;
grant execute on function public.live_join(uuid) to authenticated;
grant execute on function public.live_heartbeat(uuid, int, bigint) to authenticated;
grant execute on function public.live_end(uuid) to authenticated;
grant execute on function public.live_comment(uuid, text) to authenticated;
grant execute on function public.live_mod_action(uuid, uuid, text) to authenticated;
grant execute on function public.live_report(uuid, text) to authenticated;
grant execute on function public.admin_live_violation(uuid) to authenticated;
grant execute on function public.admin_live_unban(uuid) to authenticated;
grant execute on function public.admin_lives() to authenticated;
grant execute on function public.admin_live_penalties() to authenticated;
grant execute on function public.active_lives() to authenticated;

-- إغلاق البثوث المتروكة (أكثر من دقيقتين بدون نبض) — مع التحديث التلقائي
update public.lives set status = 'ended', ended_at = now(), ended_reason = 'timeout'
  where status = 'live' and last_beat < now() - interval '2 minutes';

-- =====================================================================
--  الإصدار 15: رسالة مثبتة في البث + حذف سجل البث
-- =====================================================================
alter table public.lives add column if not exists hidden boolean not null default false;

create or replace function public.live_set_title(p_live uuid, p_title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update lives set title = left(coalesce(trim(p_title), ''), 120)
    where id = p_live and (host_id = auth.uid() or exists(
      select 1 from live_mods m where m.host_id = lives.host_id and m.mod_id = auth.uid()));
  if not found then raise exception 'غير مسموح'; end if;
end $$;

create or replace function public.my_lives() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'status', status,
    'started_at', started_at, 'ended_at', ended_at, 'peak', peak_viewers, 'likes', like_count,
    'comments', (select count(*) from live_comments c where c.live_id = l.id)) order by started_at desc), '[]'::jsonb)
  from (select * from lives where host_id = auth.uid() and not hidden order by started_at desc limit 100) l;
$$;

-- حذف سجل البث (يختفي من سجلك وتُحذف تعليقاته؛ تبقى البلاغات عند الإدارة)
create or replace function public.live_delete(p_live uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from lives where id = p_live and host_id = auth.uid()) then raise exception 'غير مسموح'; end if;
  perform _live_close(p_live, 'host');
  delete from live_comments where live_id = p_live;
  if exists(select 1 from live_reports where live_id = p_live) then
    update lives set hidden = true where id = p_live;
  else
    delete from lives where id = p_live;
  end if;
end $$;

grant execute on function public.live_set_title(uuid, text) to authenticated;
grant execute on function public.my_lives() to authenticated;
grant execute on function public.live_delete(uuid) to authenticated;

-- =====================================================================
--  الإصدار 16: صورة/خلفية البث، والضيوف (الصعود للبث بطلب وموافقة)
-- =====================================================================
alter table public.lives add column if not exists cover_url text;

create or replace function public.live_set_cover(p_live uuid, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update lives set cover_url = nullif(trim(p_url), '') where id = p_live and host_id = auth.uid();
  if not found then raise exception 'غير مسموح'; end if;
end $$;

create table if not exists public.live_guests (
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'left')),
  updated_at timestamptz not null default now(),
  primary key (live_id, user_id)
);
alter table public.live_guests enable row level security;
drop policy if exists live_guests_select on public.live_guests;
create policy live_guests_select on public.live_guests for select to authenticated using (true);
do $$ begin
  begin execute 'alter publication supabase_realtime add table public.live_guests'; exception when others then null; end;
end $$;

create or replace function public.live_guest_request(p_live uuid) returns void
language plpgsql security definer set search_path = public as $$
declare l lives;
begin
  select * into l from lives where id = p_live;
  if l.id is null or l.status <> 'live' then raise exception 'انتهى البث'; end if;
  if l.host_id = auth.uid() then raise exception 'أنت صاحب البث'; end if;
  if is_banned() or exists(select 1 from live_bans where host_id = l.host_id and user_id = auth.uid()) then
    raise exception 'غير مسموح';
  end if;
  insert into live_guests(live_id, user_id, status) values (p_live, auth.uid(), 'pending')
    on conflict (live_id, user_id) do update set status = 'pending', updated_at = now()
    where live_guests.status <> 'accepted';
end $$;

create or replace function public.live_guest_respond(p_live uuid, p_user uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from lives where id = p_live and host_id = auth.uid()) then raise exception 'غير مسموح'; end if;
  if p_accept and (select count(*) from live_guests where live_id = p_live and status = 'accepted') >= 3 then
    raise exception 'الحد الأقصى 3 ضيوف في نفس الوقت';
  end if;
  update live_guests set status = case when p_accept then 'accepted' else 'rejected' end, updated_at = now()
    where live_id = p_live and user_id = p_user;
end $$;

-- إنزال ضيف (من صاحب البث) أو نزول الضيف بنفسه
create or replace function public.live_guest_leave(p_live uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (p_user = auth.uid() or exists(select 1 from lives where id = p_live and host_id = auth.uid())) then
    raise exception 'غير مسموح';
  end if;
  update live_guests set status = 'left', updated_at = now() where live_id = p_live and user_id = p_user;
  perform _lk_api('UpdateParticipant', p_live::text, jsonb_build_object('room', p_live::text, 'identity', p_user::text,
    'permission', jsonb_build_object('canPublish', false, 'canSubscribe', true, 'canPublishData', true)));
end $$;

create or replace function public.live_guest_token(p_live uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  if not exists(select 1 from live_guests where live_id = p_live and user_id = auth.uid() and status = 'accepted') then
    raise exception 'لم تتم الموافقة بعد';
  end if;
  select * into me from profiles where id = auth.uid();
  return jsonb_build_object('url', _lk_url(), 'token', _lk_token(auth.uid()::text, me.display_name, p_live::text, true));
end $$;

grant execute on function public.live_set_cover(uuid, text) to authenticated;
grant execute on function public.live_guest_request(uuid) to authenticated;
grant execute on function public.live_guest_respond(uuid, uuid, boolean) to authenticated;
grant execute on function public.live_guest_leave(uuid, uuid) to authenticated;
grant execute on function public.live_guest_token(uuid) to authenticated;

-- =====================================================================
--  الإصدار 17: صورة خاصة لكل ضيف على البث
-- =====================================================================
alter table public.live_guests add column if not exists cover_url text;
create or replace function public.live_guest_set_cover(p_live uuid, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update live_guests set cover_url = nullif(trim(p_url), ''), updated_at = now()
    where live_id = p_live and user_id = auth.uid() and status = 'accepted';
  if not found then raise exception 'يجب أن تكون على البث'; end if;
end $$;
grant execute on function public.live_guest_set_cover(uuid, text) to authenticated;

-- =====================================================================
--  الإصدار 18: مشاركة البث (تُحسب وتقوّي ترتيب البث)
-- =====================================================================
alter table public.lives add column if not exists share_count int not null default 0;

create or replace function public.live_share(p_live uuid) returns void
language sql security definer set search_path = public as $$
  update lives set share_count = share_count + 1 where id = p_live and status = 'live';
$$;
grant execute on function public.live_share(uuid) to authenticated;

create or replace function public.live_info(p_live uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'title', l.title, 'status',
      case when l.status = 'live' and l.last_beat > now() - interval '60 seconds' then 'live' else 'ended' end,
      'host', p.display_name, 'avatar_url', p.avatar_url)
  from lives l join profiles p on p.id = l.host_id where l.id = p_live;
$$;
grant execute on function public.live_info(uuid) to authenticated;

create or replace function public.active_lives() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'score')::numeric desc), '[]'::jsonb) from (
    select jsonb_build_object('id', l.id, 'title', l.title, 'host_id', l.host_id, 'viewers', l.viewer_count,
      'likes', l.like_count, 'shares', l.share_count, 'started_at', l.started_at,
      'score', l.viewer_count * 10 + l.like_count / 20.0 + l.share_count * 15
        + case when exists(select 1 from follows f where f.follower_id = auth.uid() and f.followee_id = l.host_id) then 500 else 0 end,
      'host', jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name,
        'avatar_url', p.avatar_url, 'is_verified', p.is_verified, 'is_owner', p.is_owner, 'xp', p.xp)) x
    from lives l join profiles p on p.id = l.host_id
    where l.status = 'live' and l.last_beat > now() - interval '60 seconds'
      and not is_blocked_between(auth.uid(), l.host_id)
    limit 100) t;
$$;

-- =====================================================================
--  الإصدار 19: الضيف يصعد/ينزل بدون إعادة اتصال (تغيير الصلاحية مباشرة في LiveKit)
-- =====================================================================
create or replace function public.live_guest_respond(p_live uuid, p_user uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from lives where id = p_live and host_id = auth.uid()) then raise exception 'غير مسموح'; end if;
  if p_accept and (select count(*) from live_guests where live_id = p_live and status = 'accepted') >= 3 then
    raise exception 'الحد الأقصى 3 ضيوف في نفس الوقت';
  end if;
  update live_guests set status = case when p_accept then 'accepted' else 'rejected' end, updated_at = now()
    where live_id = p_live and user_id = p_user;
  if p_accept then
    perform _lk_api('UpdateParticipant', p_live::text, jsonb_build_object('room', p_live::text, 'identity', p_user::text,
      'permission', jsonb_build_object('canPublish', true, 'canSubscribe', true, 'canPublishData', true,
        'canUpdateMetadata', true)));
  end if;
end $$;

-- =====================================================================
--  الإصدار 20: مشاهدة البث من الصفحة الرئيسية (معاينة بدون رسالة «انضم»)
-- =====================================================================
create or replace function public.live_preview(p_live uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l lives; me profiles;
begin
  select * into l from lives where id = p_live;
  if l.id is null or l.status <> 'live' then raise exception 'انتهى هذا البث'; end if;
  if is_banned() or is_blocked_between(auth.uid(), l.host_id)
     or exists(select 1 from live_bans where host_id = l.host_id and user_id = auth.uid()) then
    raise exception 'غير مسموح';
  end if;
  select * into me from profiles where id = auth.uid();
  return jsonb_build_object('url', _lk_url(),
    'token', _lk_token(auth.uid()::text, me.display_name, p_live::text, false),
    'host_id', l.host_id, 'title', l.title, 'cover_url', l.cover_url);
end $$;
grant execute on function public.live_preview(uuid) to authenticated;

-- =====================================================================
--  الإصدار 21: إيقاف النسخ القديمة ما يمنع النسخ الحديثة من إرسال الرسائل
--  (كان can_send يعتمد على app_enabled اللي يتعطل مع إيقاف النسخ القديمة)
-- =====================================================================
create or replace function public.can_send(conv uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  t text;
  other uuid;
begin
  if not is_member(conv) or is_banned() then return false; end if;
  if not coalesce((select service_enabled from app_settings where id = 1), true) and not is_admin() then
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

-- تحديث ذاكرة واجهة API حتى تظهر الجداول والدوال فورًا
notify pgrst, 'reload schema';
