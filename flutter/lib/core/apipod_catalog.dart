import 'provider_catalog.dart';
import 'apipod_models.dart';

export 'apipod_pricing.dart';

const apipodProvider = VideoProviderDefinition(
  id: 'apipod',
  name: 'APIPod',
  description:
      'Seedance, Veo, Kling, Wan, Grok, MiniMax, Gemini Omni, Muse and motion control.',
  consoleUrl: 'https://www.apipod.ai/console/api-keys',
  docsUrl: 'https://docs.apipod.ai/',
  pricingUrl: 'https://www.apipod.ai/pricing',
  pricingSource:
      'Published APIPod estimates; final provider usage determines cost',
  progressReporting: ProviderProgressReporting.reported,
  models: apipodModels,
);
