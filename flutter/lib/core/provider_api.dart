import 'provider_submission.dart';
import 'artcraft_api.dart';
import 'atlas_cloud_api.dart';
import 'bfl_api.dart';
import 'krea_api.dart';
import 'ltx_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'runway_api.dart';

class ProviderApiRouter {
  ProviderApiRouter({
    BflApi? bfl,
    LtxApi? ltx,
    ArtCraftApi? artcraft,
    AtlasCloudApi? atlas,
    RunwayApi? runway,
    KreaApi? krea,
  }) : bfl = bfl ?? BflApi(),
       ltx = ltx ?? LtxApi(),
       artcraft = artcraft ?? ArtCraftApi(),
       atlas = atlas ?? AtlasCloudApi(),
       runway = runway ?? RunwayApi(),
       krea = krea ?? KreaApi();

  final BflApi bfl;
  final LtxApi ltx;
  final ArtCraftApi artcraft;
  final AtlasCloudApi atlas;
  final RunwayApi runway;
  final KreaApi krea;

  String _adapter(String provider) {
    final definition = providerByIdForRouting(provider);
    if (definition == null) {
      throw ProviderException('Provider "$provider" is not available.');
    }
    return definition.adapter;
  }

  Future<ProviderAccountStatus> verify(String provider, String key) async =>
      switch (_adapter(provider)) {
        'ltx' => ltx.verify(key),
        'artcraft' => artcraft.verify(key),
        'atlas' => atlas.verify(key),
        'runway' => runway.verify(key),
        'krea' => krea.verify(key),
        'bfl' => ProviderAccountStatus(
          provider: 'bfl',
          balance: await bfl.getCredits(key),
          currency: 'credits',
        ),
        final adapter => throw ProviderException(
          'Provider adapter "$adapter" is not supported by this build.',
        ),
      };

  Future<Map<String, Object?>> submit(
    String provider,
    String key,
    String model,
    Map<String, Object?> input, {
    BeforeGenerationSend? beforeSend,
    String? operationId,
  }) => switch (_adapter(provider)) {
    'ltx' => ltx.submit(key, model, input, beforeSend: beforeSend),
    'artcraft' => artcraft.submit(
      key,
      model,
      input,
      beforeSend: beforeSend,
      operationId: operationId,
    ),
    'atlas' => atlas.submit(key, model, input, beforeSend: beforeSend),
    'runway' => runway.submit(key, model, input, beforeSend: beforeSend),
    'krea' => krea.submit(key, model, input, beforeSend: beforeSend),
    'bfl' => bfl.submit(key, input, model: model, beforeSend: beforeSend),
    final adapter => throw ProviderException(
      'Provider adapter "$adapter" is not supported by this build.',
    ),
  };

  Future<Map<String, Object?>> poll(
    String provider,
    String key,
    String pollingUrl,
  ) => switch (_adapter(provider)) {
    'ltx' => ltx.poll(key, pollingUrl),
    'artcraft' => artcraft.poll(key, pollingUrl),
    'atlas' => atlas.poll(key, pollingUrl),
    'runway' => runway.poll(key, pollingUrl),
    'krea' => krea.poll(key, pollingUrl),
    'bfl' => bfl.poll(key, pollingUrl),
    final adapter => throw ProviderException(
      'Provider adapter "$adapter" is not supported by this build.',
    ),
  };

  Future<List<ProviderModelPrice>> listModels(String provider, [String? key]) =>
      switch (_adapter(provider)) {
        'atlas' => atlas.listVideoModels(key),
        'artcraft' => artcraft.listVideoModels(),
        'runway' => runway.listVideoModels(),
        'krea' => krea.listVideoModels(),
        'bfl' || 'ltx' => Future<List<ProviderModelPrice>>.value(
          publishedProviderPrices(provider),
        ),
        final adapter => throw ProviderException(
          'Provider adapter "$adapter" is not supported by this build.',
        ),
      };

  Future<CostEstimate?> quote(
    String provider,
    String model,
    Map<String, Object?> input,
  ) => switch (_adapter(provider)) {
    'artcraft' => artcraft.estimate(model, input),
    _ => Future<CostEstimate?>.value(),
  };
}
