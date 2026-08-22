# Reference video compatibility

Clawnsole checks creative-reference videos for provider compatibility at
submission time. The toggle appears in Create → References whenever a video
reference is attached. It is enabled by default, and an explicit off choice is
remembered for future generations. The preflight applies to fresh uploads,
saved references, generated videos selected as references, and restored
generation inputs because those paths all converge on the same gateway.

The preflight probes the source before doing any conversion. A byte-for-byte
compatible MP4 is passed through unchanged. Sources that need repair are
remuxed, have only their audio repaired, or are fully transcoded as necessary.
Repaired derivatives are cached by source digest and profile version. Saved
references and generated originals are never overwritten.

Every model that accepts video references receives a conservative generic
profile. Healthy MP4 sources keep their original bytes. When repair is needed,
the generic profile preserves native display geometry, aspect ratio, and sane
constant frame rates while fixing incompatible codecs or pixel formats,
rotation and sample-aspect metadata, variable or malformed timing, HDR color,
audio, and MP4 structure.

Seedance adds the stricter `seedance-video-fix` profile: displayed orientation
selects a 720x1280, 1280x720, or 720x720 canvas; sources that retain at least
92 percent of their frame fill and crop while the rest fit and pad; HDR PQ and
HLG are tone-mapped to BT.709; video requests 30 fps H.264 High
3.1/yuv420p; audio, when present, becomes AAC-LC stereo/48 kHz; and the result
is a fast-start `isom` MP4 with zero-based timestamps. Hardware encoders that
negotiate Baseline or Main H.264 are accepted after the same strict output
validation. Packet cadence, keyframes, timestamps, codecs, dimensions, color
metadata, audio, and container structure are validated after every repair.

## Supported targets

- iOS and Android use a small Clawnsole bridge to pinned non-GPL FFmpeg 8.1.2
  mobile frameworks. iOS artifacts are checksum-verified and use VideoToolbox;
  Android uses the version-pinned Maven artifact and retries MediaCodec with
  both planar and semiplanar 4:2:0 input.
- Native Windows x64 uses a checksum-pinned LGPL FFmpeg 8.1.2 process build,
  validates PE ASLR/DEP mitigations before packaging, and falls back from
  Media Foundation to the bundled OpenH264 encoder when needed.
- Electron macOS builds pinned LGPL FFmpeg 8.1.2 and zimg 3.0.6 from verified
  source, packages and signs the tools, and uses VideoToolbox.

There is no standalone hosted-web target. A browser-only deployment could not
perform this local native preprocessing without adding a WASM or server
backend; Electron's local companion is the supported web-renderer boundary.
Windows remains x64 because that is the product's supported Windows target.

License texts and exact corresponding-source/build links are shipped with the
mobile bridge and desktop media-tool directories and are visible from
Settings → Open source licenses.
