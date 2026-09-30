-- الجزء 4 من 4 — شغّل الأجزاء بالترتيب

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
-- بعد إنشاء حسابك من التطبيق، اجعل نفسك مديرًا بتشغيل هذا السطر
-- (استبدل your_username باسم المستخدم الخاص بك):
--
--   update public.profiles set is_admin = true where username = 'your_username';
-- =====================================================================

notify pgrst, 'reload schema';
