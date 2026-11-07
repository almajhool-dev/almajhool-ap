---
name: dev-loop
description: Workflow for fixing a bug or adding a feature in the VYFRI Flutter app with minimal tokens — locate, smallest edit, targeted test, check, commit, report.
---

1. Pin the goal: what the owner will see when it's done. Ask first only if a wrong guess is expensive to redo.
2. Locate: Grep the UI string (Arabic text is a great search key), widget, provider or RPC name. Read only the matching ranges.
3. Plan the smallest change that fully solves it. Don't touch unrelated files or reformat.
4. Edit; comments in Iraqi Arabic.
5. Test: add/adjust a test in `test/` that fails before and passes after.
   - Widget tests: `MaterialApp` + RTL `Directionality`; never touch Supabase — inject loaders/savers through optional constructor params; mock platform channels (e.g. connectivity_plus) when constructing ChatHub.
   - `CacheService.init()` with `SharedPreferences.setMockInitialValues({})` in setUp; `initializeDateFormatting('ar')` when dates render.
   - FxBackground runs on real time (Stopwatch): let real time pass with `tester.runAsync(...)`; avoid `pumpAndSettle` while backgrounds animate (turn motion off with `FxSettings.instance.setMotion(false)`).
6. `tool/dev/check.sh test/<file>_test.dart` while iterating, then `tool/dev/check.sh` (full) before committing. Analyzer must stay at baseline.
7. Server involved → skill `db-change`.
8. Commit (identity in CLAUDE.md) and push. Visual change that matters → render a preview PNG from a temporary test (fonts: DejaVuSans, NotoColorEmoji, MaterialIcons from the Flutter cache), look at it, delete the temporary test.
9. Report in Iraqi Arabic: what changed for users, test results, anything the owner must do. Publish only if asked.

Pitfalls: keep the child at a fixed position in FxBackground's Stack (a remount resets navigation); guard list indexing on theme colors (photo backgrounds have none).
