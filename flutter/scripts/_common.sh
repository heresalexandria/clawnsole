#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
REPOSITORY_ROOT="$(cd "$FLUTTER_DIRECTORY/.." && pwd)"

load_public_env_value() {
  local name="$1"
  local env_file="$REPOSITORY_ROOT/.env"
  local line
  local value=""
  if [[ -n "${!name:-}" || ! -f "$env_file" ]]; then
    return
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=(.*)$ ]]; then
      value="${BASH_REMATCH[2]}"
    fi
  done <"$env_file"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ ${#value} -ge 2 ]]; then
    if [[ ( "$value" == \"*\" && "$value" == *\" ) ||
          ( "$value" == \'*\' && "$value" == *\' ) ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  if [[ -n "$value" ]]; then
    printf -v "$name" '%s' "$value"
    export "$name"
  fi
}

load_public_env_value CLAWNSOLE_SITE_URL
load_public_env_value CLAWNSOLE_MOBILE_TEST_BUILD
CLAWNSOLE_SITE_URL="${CLAWNSOLE_SITE_URL:-https://clawnsole.app/}"
CLAWNSOLE_MOBILE_TEST_BUILD="${CLAWNSOLE_MOBILE_TEST_BUILD:-false}"
export CLAWNSOLE_SITE_URL
export CLAWNSOLE_MOBILE_TEST_BUILD
CLAWNSOLE_SITE_BUILD_ARGUMENT=(
  --dart-define "CLAWNSOLE_SITE_URL=$CLAWNSOLE_SITE_URL"
)

cd "$FLUTTER_DIRECTORY"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Clawnsole needs '$1' on PATH." >&2
    exit 1
  fi
}

prepare_flutter() {
  "$REPOSITORY_ROOT/scripts/install_git_hooks" --quiet || true
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
  printf \
    'GOOGLE_IOS_CLIENT_ID = %s\nGOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.%s\n' \
    "$CLAWNSOLE_GOOGLE_IOS_CLIENT_ID" \
    "$identifier" >"$config"
}

cleanup_google_ios_oauth() {
  rm -f "$FLUTTER_DIRECTORY/ios/Flutter/GoogleDriveOAuth.xcconfig"
}
