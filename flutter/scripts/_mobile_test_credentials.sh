#!/usr/bin/env bash

# Shared iOS/Android mobile-test credential bridge. The generated Dart-define
# file is private, short-lived, and never written inside the repository.
prepare_clawnsole_mobile_test_defines() {
  MOBILE_TEST_DEFINE_FILE=""

  case "${CLAWNSOLE_MOBILE_TEST_BUILD:-false}" in
    true|TRUE|1|yes|YES)
      ;;
    false|FALSE|0|no|NO|'')
      return
      ;;
    *)
      echo "CLAWNSOLE_MOBILE_TEST_BUILD must be true or false." >&2
      exit 1
      ;;
  esac

  local key="${ARTCRAFT_TEST_KEY:-}"
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"
  if [[ -z "$key" ]]; then
    echo "ARTCRAFT_TEST_KEY is required for a mobile-test build." >&2
    exit 1
  fi
  if [[ ${#key} -gt 2000 || "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
    echo "ARTCRAFT_TEST_KEY is malformed." >&2
    exit 1
  fi

  require_command shasum
  MOBILE_TEST_DEFINE_FILE="$(umask 077; mktemp "${TMPDIR:-/tmp}/clawnsole-mobile-test.XXXXXX.env")"
  local key_id
  key_id="$(printf '%s' "$key" | shasum -a 256 | awk '{print $1}')"
  {
    printf 'CLAWNSOLE_MOBILE_TEST_BUILD=true\n'
    printf 'CLAWNSOLE_ARTCRAFT_TEST_API_KEY=%s\n' "$key"
    printf 'CLAWNSOLE_ARTCRAFT_TEST_API_KEY_ID=%s\n' "$key_id"
  } >"$MOBILE_TEST_DEFINE_FILE"
  echo "Including the version-gated ArtCraft mobile-test credential."
}

cleanup_clawnsole_mobile_test_defines() {
  if [[ -n "${MOBILE_TEST_DEFINE_FILE:-}" && -f "$MOBILE_TEST_DEFINE_FILE" ]]; then
    rm -f -- "$MOBILE_TEST_DEFINE_FILE"
  fi
}
