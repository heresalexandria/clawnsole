#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
ENV_FILE="$REPOSITORY_ROOT/.env"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./scripts/build_ios.sh [additional flutter build ipa arguments]"
  echo
  echo "Builds the production App Store IPA with the repository .env Google OAuth"
  echo "configuration. Provider test keys and custom Dart defines are prohibited."
  exit 0
fi

load_env_value() {
  local name="$1"
  local line
  local value=""
  local found=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=(.*)$ ]]; then
      value="${BASH_REMATCH[2]}"
      found=true
    fi
  done <"$ENV_FILE"

  if [[ "$found" != true ]]; then
    return
  fi

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf -v "$name" '%s' "$value"
  export "$name"
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE; it must contain the iOS Google OAuth client ID." >&2
  exit 1
fi

# Load only OAuth configuration. In particular, never source provider keys from
# .env into an App Store build process.
load_env_value CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID
load_env_value CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET
load_env_value CLAWNSOLE_GOOGLE_IOS_CLIENT_ID

if [[ -z "${CLAWNSOLE_GOOGLE_IOS_CLIENT_ID:-}" ]]; then
  echo "CLAWNSOLE_GOOGLE_IOS_CLIENT_ID must be set in $ENV_FILE." >&2
  exit 1
fi

# Production iOS builds never contain shared provider credentials, even if a
# developer's shell or .env opts into the local App Review credential flow.
export INCLUDE_IOS_TEST_KEYS=false

exec "$REPOSITORY_ROOT/flutter/scripts/build_ios" --production "$@"
