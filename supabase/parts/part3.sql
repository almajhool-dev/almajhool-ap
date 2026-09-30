-- الجزء 3 من 4 — شغّل الأجزاء بالترتيب

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

create or replace function public.admin_list_reports()
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
