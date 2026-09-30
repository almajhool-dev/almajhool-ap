-- الجزء 2 من 4 — شغّل الأجزاء بالترتيب

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

create or replace function public.get_my_conversations()
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
