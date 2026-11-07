---
name: db-change
description: Safe workflow for any backend change in supabase/schema.sql (tables, RPCs, triggers, cron) — idempotent version block, local Postgres test with role impersonation, grants, live verification.
---

The server applies the whole file in one transaction every 10 minutes: one error blocks all future updates, and every statement runs again on each update. So everything must be idempotent.

1. Next version: `grep -n "الإصدار [0-9]*:" supabase/schema.sql | tail -3`.
2. Write the block in the scratchpad (`vNN.sql`): header comment in Iraqi Arabic (what + why); `create table if not exists`; `alter table … add column if not exists`; `create or replace function` (`drop function if exists` first when the return type changes); `drop trigger if exists` + `create trigger`; cron inside `do $$ begin perform cron.schedule(...); exception when others then raise notice '%', sqlerrm; end $$;`.
3. Security:
   - Functions touching protected tables: `security definer set search_path = public`, and check the caller (`auth.uid()`, `_is_owner_me()`, membership).
   - Client RPCs: `revoke execute … from public, anon;` + `grant execute … to authenticated;`. Internal helpers: revoke from public, anon, authenticated.
   - New tables: `enable row level security`; no policy = only definer functions can use them.
   - Anything anon must call goes into the security-sweep allowlist (`allow_anon`).
4. Insert the block right BEFORE the anchor line `--  الحارس الأمني (لازم يبقى آخر شي بالملف` (and its `-- ====` line above). Never after it.
5. `tool/dev/localdb.sh` → must print `apply 1 OK` and `apply 2 OK`.
6. E2E test file in the scratchpad, fed through stdin: `sudo -u postgres psql -p 5432 -d sb < file.sql` (`-f` can't read the scratchpad).
   - Seed users with `insert into auth.users(id,email,raw_user_meta_data)` (profiles are created by trigger); disable user triggers for bulk seeds.
   - Impersonate inside one transaction: `begin; set local role authenticated; select set_config('request.jwt.claim.sub','<uuid>',true); … commit;` — anon: `set local role anon`. The superuser bypasses RLS, so always impersonate.
   - Race-sensitive logic: two `dblink` connections. Clean up test rows at the end.
7. After pushing: `tool/dev/live.sh <new_function> '{"arg":"dummy"}' wait` until LIVE (pass the real argument names).
