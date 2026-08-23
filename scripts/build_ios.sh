#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
ENV_FILE="$REPOSITORY_ROOT/.env"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./scripts/build_ios.sh [additional flutter build ipa arguments]"
  echo
  echo "Builds the production App Store IPA with Google OAuth configuration from"
  echo "the environment or repository .env. Provider test keys and custom Dart"
  echo "defines are prohibited."
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

# Load only OAuth configuration. In particular, never source provider keys from
# .env into an App Store build process. Preconfigured environment values take
# precedence so ephemeral CI runners do not need a secret-bearing .env file.
for name in \
  CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID \
  CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET \
  CLAWNSOLE_GOOGLE_IOS_CLIENT_ID; do
  if [[ -z "${!name:-}" && -f "$ENV_FILE" ]]; then
    load_env_value "$name"
  fi
done

if [[ -z "${CLAWNSOLE_GOOGLE_IOS_CLIENT_ID:-}" ]]; then
  echo "CLAWNSOLE_GOOGLE_IOS_CLIENT_ID must be set in the environment or $ENV_FILE." >&2
  exit 1
fi

# Production iOS builds never contain shared provider credentials, even if a
# developer's shell or .env opts into the local App Review credential flow.
export INCLUDE_IOS_TEST_KEYS=false

exec "$REPOSITORY_ROOT/flutter/scripts/build_ios" --production "$@"
