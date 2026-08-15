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
