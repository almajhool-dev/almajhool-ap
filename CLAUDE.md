# VYFRI (almajhool-app) — guide for Claude

Flutter app (Android first, iOS builds too) + Supabase backend. Owner: Gdhfr.

## Always
- Talk to the owner ONLY in Iraqi Arabic — every message, even one-line status. Code comments in Iraqi Arabic like the rest of the repo.
- Commit as `git -c user.name=almajhool-dev -c user.email=almajhool-dev@users.noreply.github.com commit …` with NO Co-Authored-By / Claude-Session lines.
- Publish a version or delete data ONLY when the owner explicitly asks («انشر», «حدث نسخة»…). Publishing = skill `ship-release`. Never delete branch `ci-verify`.
- Never print/commit secrets; never open the Firebase service-account JSON or `signing/`. Never ask the owner for keys or invent credentials.
- The owner's private phone/emails never go into code, schema, site or chat.
- Privacy by design: the app keeps no per-user IP/device/location — don't build features that expose them. AI persona accounts stay labelled 🤖 and defensive-only.
- Don't install new tools/packages without the owner's OK (the Flutter SDK below is the project toolchain).

## Map
- `lib/` app. Large files — never read whole: `screens/chat/chat_screen.dart`, `screens/admin/admin_screen.dart`, `providers/providers.dart` (ChatHub, AppStatusProvider, SessionProvider), `widgets/fx.dart` + `services/fx_settings.dart` (app-wide background).
- `supabase/schema.sql` (~13k lines) = the whole backend. The server re-applies the FULL file from GitHub `main` every 10 min in ONE transaction → one SQL error blocks every future server update. Changes: skill `db-change`.
- `test/` unit + widget tests. `tool/dev/` helper scripts. `release/control.json` = the version users get (only `tool/dev/ship.sh` changes it).
- CI on push to main: Build APK, iOS, Startup test (`*.md` ignored). Add `[skip ci]` to commits that don't change the app.

## Save tokens
- Grep first, then read only the hit range (Read offset/limit or `sed -n 'a,bp'`). Never read schema.sql whole.
- Don't re-read what is already in context; recall changes with `git diff --stat` / `git diff <file>`.
- Filter long outputs; prefer `tool/dev/check.sh` (prints failures + summary only).
- Iterate on the touched test file; full suite once before committing.
- Read the error before retrying; never repeat a failing command unchanged.
- Open a skill only when its task comes up.

## Scripts (`tool/dev/`)
- `check.sh [test files…]` — analyze (baseline: 5 infos, all in push_service.dart) + tests, compact.
- `localdb.sh [--fresh]` — start local Postgres 16, create DB `sb` from `supabase_stubs.sql` if missing, apply schema.sql twice.
- `live.sh <function> ['{json args}'] [wait]` — is a server function deployed? LIVE / MISSING.
- `ship.sh <sha> "<msg>"` — waits for CI, checks the APK signer, publishes. Owner's request only.

## Skills (`.claude/skills/`)
`dev-loop` (bug/feature) · `db-change` (schema.sql) · `ship-release` (publishing).

## Environment
- Flutter: `export PATH=/home/claude/sdk/flutter/bin:$PATH` (if missing in a new session: clone the stable channel there; CI uses stable).
- `gh` CLI works for `almajhool-dev/almajhool-ap`.
- The Supabase connector has NO permission on this project → test locally (`localdb.sh`), verify live with `live.sh` / anon REST. Public URL + publishable key: `lib/core/config.dart`.
