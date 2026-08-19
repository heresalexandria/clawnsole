# Apple Local generation

This Swift package is the shared Apple-system generation runtime for
Clawnsole's iOS app and Electron macOS companion.

- Pixel generation uses Apple's programmatic Image Playground `ImageCreator`
  API with Illustration style. There is no API key or separately hosted
  Clawnsole service.
- Image mode writes one PNG. Apple Local animation is retired from the product,
  and shared request validation rejects legacy animation submissions before
  Image Playground is opened.

The provider is available when Apple Image Playground's programmatic creator is
available: iOS/iPadOS 18.4+ or macOS 15.4+ on an Apple Intelligence-capable
device with image creation enabled. Unsupported systems keep the cloud
providers available and hide Apple Local. On macOS, Apple requires image
creation to remain foreground work, so the bundled helper app displays a small
progress window until the job completes.
