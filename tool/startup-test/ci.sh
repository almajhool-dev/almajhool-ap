#!/usr/bin/env bash
bash _t/tool/startup-test/run.sh app > startup.log 2>&1
R=$?
adb exec-out screencap -p > shot.png
cat startup.log
if grep -qE "NoSuchMethodError|FATAL EXCEPTION|STARTUP: FAIL" startup.log; then exit 1; fi
exit $R
