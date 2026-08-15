#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELECTRON_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
REPOSITORY_ROOT="$(cd "$ELECTRON_DIRECTORY/.." && pwd)"
FLUTTER_DIRECTORY="$REPOSITORY_ROOT/flutter"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Clawnsole needs '$1' on PATH." >&2
    exit 1
  fi
}

prepare_dependencies() {
  require_command flutter
  require_command npm
  (cd "$FLUTTER_DIRECTORY" && flutter pub get)
  npm install --prefix "$ELECTRON_DIRECTORY"
}

print_heading() {
  echo
  echo "Clawnsole · $1"
  echo "Working directory: $REPOSITORY_ROOT"
  echo
}
