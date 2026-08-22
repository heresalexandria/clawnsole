#!/usr/bin/env bash

set -euo pipefail

VERSION="8.1.2"
BASE_URL="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/${VERSION}-full"
FRAMEWORKS=(
  "ffmpegkit:a565f36d1d6769523fe78aee3c015212ea7f9b1fc1007bea21e46c1d6df06bde"
  "libavcodec:eb56ac124c03ebd4c91584b86fe3c6d758ed1cff1cf475cc6bca319f0f7c8106"
  "libavdevice:0f1f06f636beb75936e5f840f81ec15966fb1dfaff14f78cb83bdbcc3422bb89"
  "libavfilter:50eb73ebe41724444b8256c2c61541ced3fda7b2e1b20aac2f928fb2bf2d0ac6"
  "libavformat:e9f08440c7e0aa3fba67e1f9f1f4c06a6fb2b9da557953fd086b2343dda6b31a"
  "libavutil:70d35584a0ee9282bdbb6b02f3ce806f6ceb27b81cf148905642b468a40bfec6"
  "libswresample:df15ca091b005cc984f644c68d6617ac6b9588992fa8387bb068c4f1c8a6d0be"
  "libswscale:2570aab53ad07282e3539dff906d73a9c801589b1d3b33870df0ccbe892c4b07"
)

if [[ -d "Frameworks/ffmpegkit.xcframework" ]]; then
  exit 0
fi

WORKING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/clawnsole-ios-media.XXXXXX")"
cleanup() {
  rm -rf "$WORKING_DIRECTORY"
}
trap cleanup EXIT
mkdir -p "$WORKING_DIRECTORY/Frameworks"

for item in "${FRAMEWORKS[@]}"; do
  name="${item%%:*}"
  expected="${item#*:}"
  archive="$WORKING_DIRECTORY/$name.zip"
  curl --fail --location --retry 3 --connect-timeout 30 \
    "$BASE_URL/$name.xcframework.zip" --output "$archive"
  echo "$expected  $archive" | shasum -a 256 --check
  unzip -q "$archive" -d "$WORKING_DIRECTORY/unpacked-$name"
  source_path="$WORKING_DIRECTORY/unpacked-$name/$name.xcframework"
  if [[ ! -d "$source_path" ]]; then
    echo "The $name iOS framework archive is malformed." >&2
    exit 1
  fi
  mv "$source_path" "$WORKING_DIRECTORY/Frameworks/"
done

rm -rf Frameworks
mv "$WORKING_DIRECTORY/Frameworks" Frameworks
