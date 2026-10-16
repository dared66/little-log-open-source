#!/usr/bin/env bash
set -euo pipefail
# Compile the memory-only care harness, and reject physical-device execution.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
serial="${1:?Pass a disposable QA emulator ID explicitly.}"
if [[ "$serial" == emulator-5580 ]]; then
  echo 'The shared review emulator is protected. Use a disposable QA emulator.' >&2
  exit 1
fi
case "$serial" in emulator-*) ;; *) echo 'Use an Android emulator.' >&2; exit 1;; esac
if [[ "$(adb -s "$serial" shell getprop ro.kernel.qemu | tr -d '\r')" != 1 ]]; then
  echo 'This device is not an emulator.' >&2
  exit 1
fi
artifact_dir="${2:-$repo_dir/build/voice-action-qa}"
mkdir -p "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
cd "$repo_dir/android"
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest -Ptarget="$repo_dir/tool/voice_action_review.dart"
cd "$repo_dir"
adb -s "$serial" install -r build/app/outputs/apk/debug/app-debug.apk
adb -s "$serial" install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$serial" shell pm grant app.littlelog.little_log android.permission.POST_NOTIFICATIONS
adb -s "$serial" shell am instrument -w -r -e isolatedVoiceQa true \
  -e class app.littlelog.little_log.AssistantActionsTest,app.littlelog.little_log.VoiceEntryPointsTest,app.littlelog.little_log.ExternalActionSecurityTest \
  app.littlelog.little_log.test/androidx.test.runner.AndroidJUnitRunner | tee "$artifact_dir/result.log"
grep -q 'OK (21 tests)' "$artifact_dir/result.log"
