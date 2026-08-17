#!/usr/bin/env bash

# Shared, silent App Review/development credential bridge. The generated file
# is mode 0600, never logged, and deleted by the calling script's EXIT trap.
load_clawnsole_review_credentials() {
  local review_env_file="${CLAWNSOLE_IOS_REVIEW_ENV_FILE:-$FLUTTER_DIRECTORY/.env.ios-review}"
  if [[ -f "$review_env_file" ]]; then
    # shellcheck disable=SC1090
    source "$review_env_file"
  fi
  if [[ -f "$REPOSITORY_ROOT/.env" ]]; then
    # shellcheck disable=SC1090
    source "$REPOSITORY_ROOT/.env"
  fi
  if [[ -z "${CLAWNSOLE_IOS_REVIEW_BFL_API_KEY:-}" &&
        -r "${CLAWNSOLE_IOS_REVIEW_BFL_API_KEY_FILE:-}" ]]; then
    CLAWNSOLE_IOS_REVIEW_BFL_API_KEY="$(<"$CLAWNSOLE_IOS_REVIEW_BFL_API_KEY_FILE")"
  fi
  if [[ -z "${CLAWNSOLE_IOS_REVIEW_LTX_API_KEY:-}" &&
        -r "${CLAWNSOLE_IOS_REVIEW_LTX_API_KEY_FILE:-}" ]]; then
    CLAWNSOLE_IOS_REVIEW_LTX_API_KEY="$(<"$CLAWNSOLE_IOS_REVIEW_LTX_API_KEY_FILE")"
  fi
  if [[ -z "${CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY:-}" &&
        -r "${CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY_FILE:-}" ]]; then
    CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY="$(<"$CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY_FILE")"
  fi
}

prepare_clawnsole_review_defines() {
  REVIEW_DEFINE_FILE=""
  REVIEW_BUILD_ARGUMENTS=()

  local bfl_key="${CLAWNSOLE_IOS_REVIEW_BFL_API_KEY:-${BFL_API_KEY:-}}"
  local ltx_key="${CLAWNSOLE_IOS_REVIEW_LTX_API_KEY:-${LTX_API_KEY:-}}"
  local atlas_key="${CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY:-${ATLAS_CLOUD_KEY:-}}"

  _append_clawnsole_review_define "BFL" "$bfl_key"
  _append_clawnsole_review_define "LTX" "$ltx_key"
  _append_clawnsole_review_define "ATLAS" "$atlas_key"

  if [[ -n "$REVIEW_DEFINE_FILE" ]]; then
    REVIEW_BUILD_ARGUMENTS+=(--dart-define-from-file "$REVIEW_DEFINE_FILE")
    echo "Including configured App Review provider credentials."
  else
    echo "No App Review credentials are configured; this build will require user keys."
  fi
}

_append_clawnsole_review_define() {
  local provider="$1"
  local key="$2"
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"
  [[ -z "$key" ]] && return
  if [[ ${#key} -gt 2000 || "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
    echo "The $provider App Review key is malformed." >&2
    exit 1
  fi
  require_command shasum
  if [[ -z "$REVIEW_DEFINE_FILE" ]]; then
    REVIEW_DEFINE_FILE="$(umask 077; mktemp "${TMPDIR:-/tmp}/clawnsole-ios-review.XXXXXX.env")"
  fi
  local key_id
  key_id="$(printf '%s' "$key" | shasum -a 256 | awk '{print $1}')"
  printf 'CLAWNSOLE_IOS_REVIEW_%s_API_KEY=%s\n' "$provider" "$key" >>"$REVIEW_DEFINE_FILE"
  printf 'CLAWNSOLE_IOS_REVIEW_%s_API_KEY_ID=%s\n' "$provider" "$key_id" >>"$REVIEW_DEFINE_FILE"
}

cleanup_clawnsole_review_defines() {
  if [[ -n "${REVIEW_DEFINE_FILE:-}" && -f "$REVIEW_DEFINE_FILE" ]]; then
    rm -f -- "$REVIEW_DEFINE_FILE"
  fi
}
