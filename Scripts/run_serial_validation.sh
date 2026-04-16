#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/EnglishBuddy.xcodeproj"
DEVICE_DESTINATION="${ENGLISHBUDDY_VALIDATION_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro Max}"

run_step() {
  local label="$1"
  shift
  echo "==> ${label}" >&2
  "$@"
}

handle_failure() {
  local exit_code="$1"
  if [[ "${exit_code}" -ne 0 ]]; then
    echo "Serial validation failed. If you saw 'database is locked', do not rerun builds in parallel." >&2
  fi
  exit "${exit_code}"
}

trap 'handle_failure $?' EXIT

run_step \
  "Build EnglishBuddy" \
  xcodebuild -project "${PROJECT_PATH}" -scheme EnglishBuddy -destination 'generic/platform=iOS' build

run_step \
  "Run unit tests" \
  xcodebuild -project "${PROJECT_PATH}" -scheme EnglishBuddy -destination "${DEVICE_DESTINATION}" test

if [[ "${ENGLISHBUDDY_SKIP_UI_TESTS:-0}" != "1" ]]; then
  run_step \
    "Run UI smoke tests" \
    xcodebuild -project "${PROJECT_PATH}" -scheme EnglishBuddyAutomation -destination "${DEVICE_DESTINATION}" test
fi

trap - EXIT
echo "Serial validation completed successfully." >&2
