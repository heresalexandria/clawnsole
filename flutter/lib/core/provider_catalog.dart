import 'models.dart';

class VideoProviderDefinition {
  const VideoProviderDefinition({
    required this.id,
    required this.name,
    required this.model,
    required this.modelLabel,
    required this.description,
    required this.modes,
    required this.aspectRatios,
    required this.minDuration,
    required this.maxDuration,
    required this.maxKeyframes,
    required this.docsUrl,
    required this.pricingUrl,
  });

  final String id;
  final String name;
  final String model;
  final String modelLabel;
  final String description;
  final List<VideoMode> modes;
  final List<String> aspectRatios;
  final int minDuration;
  final int maxDuration;
  final int maxKeyframes;
  final String docsUrl;
  final String pricingUrl;
}

const bflProvider = VideoProviderDefinition(
  id: 'bfl',
  name: 'Black Forest Labs',
  model: 'flux-3-video',
  modelLabel: 'FLUX 3',
  description: 'Multimodal video with synchronized audio and keyframe control.',
  modes: VideoMode.values,
  aspectRatios: <String>[
    'auto',
    '21:9',
    '2:1',
    '16:9',
    '4:3',
    '1:1',
    '3:4',
    '9:16',
  ],
  minDuration: 5,
  maxDuration: 20,
  maxKeyframes: 10,
  docsUrl: 'https://docs.bfl.ai/flux_3/flux3_video',
  pricingUrl: 'https://bfl.ai/pricing',
);
