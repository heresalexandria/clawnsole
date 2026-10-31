import 'fal_model_contracts.dart';
import 'models.dart';
import 'provider_catalog.dart';

const falProvider = VideoProviderDefinition(
  id: 'fal',
  name: 'fal',
  description: 'FLUX 3 Max and current video models through fal’s queued API.',
  consoleUrl: 'https://fal.ai/dashboard/keys',
  docsUrl: 'https://fal.ai/docs/model-apis',
  pricingUrl: 'https://fal.ai/pricing',
  pricingSource: 'Published list rates; fal promotions may reduce charges',
  models: falModelDefinitions,
);

/// Resolution-specific published list prices, audited on 2026-10-30.
///
/// fal's pricing API exposes only a base billing unit, without the resolution
/// adjustments needed to quote these endpoints. Temporary promotions also have
/// no published UTC cutoff. Keep these conservative list estimates explicit;
/// do not turn an ambiguous base unit or promotion into a precise charge.
List<ProviderModelPrice> falPublishedPrices() => <ProviderModelPrice>[
  for (final spec in falRouteSpecs.values)
    for (final resolution in spec.resolutions)
      ProviderModelPrice(
        provider: 'fal',
        model: '${spec.id}:${resolution.id}',
        canonicalModelId: spec.canonicalId,
        label: '${spec.label} · ${resolution.label}',
        usdPerSecond: spec.listUsdPerSecond[resolution.id]!,
        referenceUsdPerSecond: spec.supportsStartFrame
            ? spec.listUsdPerSecond[resolution.id]
            : null,
        modes: spec.modes,
        source:
            'Published list rates; fal promotions may reduce charges'
            '${spec.family == FalModelFamily.h3 ? '; generated duration may exceed the request by about 0.7s' : ''}',
        minDuration: spec.minDuration,
        maxDuration: spec.maxDurationFor(resolution.id),
        durationStep: spec.durationStep,
      ),
];
