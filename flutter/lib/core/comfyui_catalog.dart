import 'models.dart';
import 'provider_catalog.dart';

const comfyUiProvider = VideoProviderDefinition(
  id: 'comfyui',
  name: 'ComfyUI',
  description:
      'Run your own image and video workflows on a local, LAN, or Tailscale server.',
  consoleUrl: 'https://www.comfy.org/',
  docsUrl: 'https://docs.comfy.org/',
  pricingUrl: 'https://www.comfy.org/',
  pricingSource: 'Your hardware · no Clawnsole provider charge',
  requiresApiKey: false,
  requiresConfiguration: true,
  resultDelivery: ProviderResultDelivery(requiresRetentionForPlayback: true),
  models: [
    VideoModelDefinition(
      id: 'comfyui-video',
      label: 'Video workflow',
      description:
          'An imported API workflow, such as your installed H3 or LTX graph.',
      generationNotice:
          'Your imported workflow selects the model and controls rendering. Output controls affect only inputs you mapped with workflow placeholders. Keep the server running until the result is saved.',
      modes: [VideoMode.t2v],
      aspectRatios: ['16:9', '4:3', '1:1', '3:4', '9:16'],
      resolutions: [
        VideoResolutionDefinition(
          'hd',
          '768 px',
          'Long edge; mapped dimensions align to 64 px',
        ),
        VideoResolutionDefinition(
          'fhd',
          '1024 px',
          'Long edge; mapped dimensions align to 64 px',
        ),
      ],
      minDuration: 1,
      maxDuration: 20,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: 0,
      supportsAudio: false,
      supportsSeed: true,
    ),
    VideoModelDefinition(
      id: 'comfyui-image',
      label: 'Image workflow',
      description: 'An imported API workflow with a SaveImage output.',
      generationNotice:
          'Your imported workflow selects the model and controls rendering. Output controls affect only inputs you mapped with workflow placeholders. Keep the server running until the result is saved.',
      modes: [VideoMode.t2v],
      aspectRatios: ['16:9', '4:3', '1:1', '3:4', '9:16'],
      resolutions: [
        VideoResolutionDefinition(
          'hd',
          '768 px',
          'Long edge; mapped dimensions align to 64 px',
        ),
        VideoResolutionDefinition(
          'fhd',
          '1024 px',
          'Long edge; mapped dimensions align to 64 px',
        ),
      ],
      minDuration: 1,
      maxDuration: 1,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: 0,
      supportsAudio: false,
      supportsSeed: true,
      outputKind: GenerationOutputKind.image,
    ),
  ],
);
