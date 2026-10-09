#!/usr/bin/env bash
set -euo pipefail

sdk_path="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_path" || ! -x "$sdk_path/emulator/emulator" ]]; then
  echo "Set ANDROID_HOME to your Android SDK directory, or use Android Studio Device Manager." >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <avd-name> [emulator-options...]" >&2
  "$sdk_path/emulator/emulator" -list-avds
  exit 1
fi
avd_name="$1"
shift
exec "$sdk_path/emulator/emulator" -avd "$avd_name" "$@"
