#!/usr/bin/env bash
set -euo pipefail
# Native picker QA always compiles the in-memory harness and rejects real devices.
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
artifact_dir="${2:-$repo_dir/build/import-picker-qa}"
mkdir -p "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
cd "$repo_dir/android"
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest -Ptarget="$repo_dir/tool/import_picker_review.dart"
cd "$repo_dir"
adb -s "$serial" push test/fixtures/nara_export.csv /sdcard/Download/Nara-Robin-test.csv
adb -s "$serial" install -r build/app/outputs/apk/debug/app-debug.apk
adb -s "$serial" install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$serial" shell am instrument -w -r -e isolatedImportQa true -e class app.littlelog.little_log.ImportPickerTest app.littlelog.little_log.test/androidx.test.runner.AndroidJUnitRunner | tee "$artifact_dir/result.log"
adb -s "$serial" pull /sdcard/Android/data/app.littlelog.little_log/files/ "$artifact_dir/"
grep -q 'OK (1 test)' "$artifact_dir/result.log"
