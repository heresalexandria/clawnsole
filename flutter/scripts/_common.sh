#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
REPOSITORY_ROOT="$(cd "$FLUTTER_DIRECTORY/.." && pwd)"

cd "$FLUTTER_DIRECTORY"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Clawnsole needs '$1' on PATH." >&2
    exit 1
  fi
}

prepare_flutter() {
  require_command flutter
  flutter pub get
}

print_heading() {
  echo
  echo "Clawnsole · $1"
  echo "Working directory: $FLUTTER_DIRECTORY"
  echo
}

prepare_google_ios_oauth() {
  local config="$FLUTTER_DIRECTORY/ios/Flutter/GoogleDriveOAuth.xcconfig"
  rm -f "$config"
  if [[ -z "${CLAWNSOLE_GOOGLE_IOS_CLIENT_ID:-}" ]]; then
    return
  fi
  local suffix=".apps.googleusercontent.com"
  local identifier="${CLAWNSOLE_GOOGLE_IOS_CLIENT_ID%$suffix}"
  if [[ "$identifier" == "${CLAWNSOLE_GOOGLE_IOS_CLIENT_ID}" ]]; then
    echo "CLAWNSOLE_GOOGLE_IOS_CLIENT_ID is not a Google OAuth client ID." >&2
    exit 1
  fi
  printf 'GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.%s\n' \
    "$identifier" >"$config"
}

cleanup_google_ios_oauth() {
  rm -f "$FLUTTER_DIRECTORY/ios/Flutter/GoogleDriveOAuth.xcconfig"
}
