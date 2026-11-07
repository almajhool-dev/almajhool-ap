---
name: ship-release
description: Publish a new VYFRI app version to users, only when the owner explicitly asks — wait for CI, verify the APK signer, flip release/control.json, confirm on the server.
---

Only when the owner asks («انشر», «حدث نسخة», «انشر نسخة»). Never on your own initiative.

1. The feature commit must be on GitHub: `git log origin/main -1 --format=%H`.
2. Run in the background (Bash `run_in_background`, timeout 1h):
   `bash tool/dev/ship.sh <full-sha> "<short Arabic summary>" > <scratchpad>/ship.log 2>&1; echo "exit=$?" >> <scratchpad>/ship.log`
   It waits for "Build APK" and "Startup test" (dispatches the test if missing), downloads the APK, checks the signer fingerprint (starts `17:D4:60:1E`), writes release/control.json, commits as almajhool-dev, pushes, then polls `latest_release` until the server reports the build.
3. Results: `exit=2` build failed · `exit=3` startup test failed · `exit=4` wrong signature → STOP, tell the owner, never publish · `NOTLIVE` = pushed but the server isn't reporting it yet.
4. Tell the owner in Iraqi Arabic: version number, tests passed, signature matches, live on the server.
