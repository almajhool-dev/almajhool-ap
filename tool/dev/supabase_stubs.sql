-- محاكاة بيئة Supabase محليًا (للاختبار فقط)
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
grant usage on schema public to anon, authenticated, service_role;
-- مثل Supabase: الجداول والدوال الجديدة تجي بصلاحيات كاملة للأدوار (والحارس الأمني يقفلها)
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
do $$ begin execute format('alter database %I set search_path = "$user", public, extensions', current_database()); end $$;

-- http (pgsql-http) — يرجع رد ثابت؛ الاختبارات تبدّل extensions.http حسب الحاجة
create type extensions.http_header as (field varchar, value varchar);
create type extensions.http_request as (method text, uri varchar, headers extensions.http_header[], content_type varchar, content varchar);
create type extensions.http_response as (status integer, content_type varchar, headers extensions.http_header[], content varchar);
create function extensions.http_header(field varchar, value varchar) returns extensions.http_header
  language sql immutable as $$ select row(field, value)::extensions.http_header $$;
create function extensions.http(request extensions.http_request) returns extensions.http_response
  language sql as $$ select row(503, 'text/plain', null, 'offline')::extensions.http_response $$;
create function extensions.http_get(uri varchar) returns extensions.http_response
  language sql as $$ select row(503, 'text/plain', null, null)::extensions.http_response $$;
create function extensions.http_post(uri varchar, content varchar, content_type varchar) returns extensions.http_response
  language sql as $$ select row(503, 'text/plain', null, null)::extensions.http_response $$;
create function extensions.http_set_curlopt(curlopt varchar, value varchar) returns boolean language sql as $$ select true $$;

-- pg_net
create schema if not exists net;
create table net.http_request_queue(id bigserial primary key, method text, url text, headers jsonb, body bytea, timeout_milliseconds int);
create table net._http_response(id bigint primary key, status_code int, content_type text, headers jsonb, content text,
  timed_out bool, error_msg text, created timestamptz not null default now());
create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds int default 5000) returns bigint
  language sql as $$ insert into net.http_request_queue(method, url, headers, timeout_milliseconds) values ('POST', url, headers, timeout_milliseconds) returning id $$;
create function net.http_get(url text, params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb,
  timeout_milliseconds int default 5000) returns bigint
  language sql as $$ insert into net.http_request_queue(method, url, headers, timeout_milliseconds) values ('GET', url, headers, timeout_milliseconds) returning id $$;
grant usage on schema net to anon, authenticated, service_role;

-- pg_cron
create schema if not exists cron;
create table cron.job(jobid bigserial primary key, schedule text, command text, nodename text default 'localhost',
  nodeport int default 5432, database text default current_database(), username text default current_user,
  active boolean default true, jobname text unique);
create table cron.job_run_details(jobid bigint, runid bigserial primary key, job_pid int, database text, username text,
  command text, status text, return_message text, start_time timestamptz, end_time timestamptz);
create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $$;
create function cron.unschedule(job_name text) returns boolean language sql as $$
  with d as (delete from cron.job where jobname = job_name returning 1) select exists(select 1 from d) $$;
create function cron.unschedule(job_id bigint) returns boolean language sql as $$
  with d as (delete from cron.job where jobid = job_id returning 1) select exists(select 1 from d) $$;

-- auth
create schema if not exists auth;
create table auth.users(
  instance_id uuid, id uuid primary key default gen_random_uuid(), aud varchar(255) default 'authenticated',
  role varchar(255) default 'authenticated', email varchar(255), encrypted_password varchar(255),
  email_confirmed_at timestamptz, invited_at timestamptz, confirmation_token varchar(255), confirmation_sent_at timestamptz,
  recovery_token varchar(255), recovery_sent_at timestamptz, email_change_token_new varchar(255), email_change varchar(255),
  email_change_sent_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}',
  is_super_admin boolean, created_at timestamptz default now(), updated_at timestamptz default now(), phone text unique,
  phone_confirmed_at timestamptz, phone_change text default '', phone_change_token varchar(255) default '',
  phone_change_sent_at timestamptz, confirmed_at timestamptz, email_change_token_current varchar(255) default '',
  email_change_confirm_status smallint default 0, banned_until timestamptz, reauthentication_token varchar(255) default '',
  reauthentication_sent_at timestamptz, is_sso_user boolean default false, deleted_at timestamptz, is_anonymous boolean default false);
create table auth.identities(provider_id text not null, user_id uuid not null references auth.users(id) on delete cascade,
  identity_data jsonb not null, provider text not null, last_sign_in_at timestamptz, created_at timestamptz default now(),
  updated_at timestamptz default now(), email text, id uuid primary key default gen_random_uuid(), unique(provider_id, provider));
create table auth.sessions(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(), updated_at timestamptz default now(), factor_id uuid, aal text, not_after timestamptz);
create table auth.refresh_tokens(instance_id uuid, id bigserial primary key, token varchar(255), user_id varchar(255),
  revoked boolean, created_at timestamptz default now(), updated_at timestamptz default now(), parent varchar(255),
  session_id uuid references auth.sessions(id) on delete cascade);
create table auth.audit_log_entries(instance_id uuid, id uuid primary key default gen_random_uuid(), payload json,
  created_at timestamptz default now(), ip_address varchar(64) default '');
create table auth.mfa_factors(id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade,
  friendly_name text, factor_type text, status text, created_at timestamptz default now(), updated_at timestamptz default now(), secret text);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(coalesce(current_setting('request.jwt.claim.sub', true), current_setting('request.jwt.claims', true)::jsonb->>'sub'), '')::uuid $$;
create function auth.role() returns text language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_setting('request.jwt.claims', true)::jsonb->>'role') $$;
create function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.email() returns text language sql stable as $$ select auth.jwt()->>'email' $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;

-- storage
create schema if not exists storage;
create table storage.buckets(id text primary key, name text not null unique, owner uuid, created_at timestamptz default now(),
  updated_at timestamptz default now(), public boolean default false, avif_autodetection boolean default false,
  file_size_limit bigint, allowed_mime_types text[], owner_id text);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(), metadata jsonb, path_tokens text[] generated always as (string_to_array(name, '/')) stored,
  version text, owner_id text, user_metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
create function storage.filename(name text) returns text language sql immutable as
  $$ select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)] $$;
create function storage.extension(name text) returns text language sql immutable as
  $$ select reverse(split_part(reverse(storage.filename(name)), '.', 1)) $$;
grant usage on schema storage to anon, authenticated, service_role;
grant all on all tables in schema storage to anon, authenticated, service_role;

-- realtime
do $$ begin create publication supabase_realtime; exception when duplicate_object then null; end $$;

-- لاختبارات التزامن (اتصالين بنفس الوقت)
create extension if not exists dblink;
