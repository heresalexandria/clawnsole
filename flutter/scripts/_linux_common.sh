#!/usr/bin/env bash

# Shared native Linux build requirements; no provider credentials are loaded.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_linux() {
  if [[ "$(uname -s)" != Linux ]]; then
    echo "The native Clawnsole Linux app must be built and run on Linux." >&2
    exit 1
  fi
  case "$(uname -m)" in
    x86_64) LINUX_ARCH=x64; DEBIAN_ARCH=amd64 ;;
    aarch64 | arm64) LINUX_ARCH=arm64; DEBIAN_ARCH=arm64 ;;
    *) echo "Clawnsole Linux supports x64 and ARM64." >&2; exit 1 ;;
  esac
}

prepare_linux() {
  require_linux
  for command in clang cmake ninja pkg-config ffmpeg ffprobe; do
    require_command "$command"
  done
  if ! pkg-config --exists gtk+-3.0 libsecret-1 mpv epoxy; then
    echo "Install libgtk-3-dev libsecret-1-dev libmpv-dev libepoxy-dev." >&2
    exit 1
  fi
  prepare_flutter
}

linux_oauth_arguments() {
  LINUX_OAUTH_ARGUMENTS=()
  if [[ -n "${CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID:-}" ]]; then
    LINUX_OAUTH_ARGUMENTS+=(
      --dart-define "CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID=${CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID}"
    )
  fi
  if [[ -n "${CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]]; then
    LINUX_OAUTH_ARGUMENTS+=(
      --dart-define "CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET=${CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET}"
    )
  fi
}
