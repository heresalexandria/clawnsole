# Apple Local generation

This Swift package is the shared Apple-system generation runtime for
Clawnsole's iOS app and Electron macOS companion.

- Pixel generation uses Apple's programmatic Image Playground `ImageCreator`
  API with Illustration style for stills and Animation style for frames. There
  is no API key or separately hosted Clawnsole service.
- On iOS/macOS 26 or newer, Apple's Foundation Models framework expands the
  user's prompt into a continuity-locked art-direction prompt. Earlier systems
  use a deterministic continuity template.
- Image mode writes one PNG. Experimental animation mode generates
  `duration × frameRate` PNG frames, conditions each new frame on the previous
  frame as an image concept, then encodes a silent H.264 MP4 locally.

The provider is available when Apple Image Playground's programmatic creator is
available: iOS/iPadOS 18.4+ or macOS 15.4+ on an Apple Intelligence-capable
device with image creation enabled. Unsupported systems keep the cloud
providers available and hide Apple Local. On macOS, Apple requires image
creation to remain foreground work, so the bundled helper app displays a small
progress window until the job completes.
