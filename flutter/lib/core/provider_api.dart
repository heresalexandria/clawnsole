import 'provider_submission.dart';
import 'comfyui_api.dart';
import 'comfyui_settings.dart';
import 'apipod_api.dart';
import 'artcraft_api.dart';
import 'atlas_cloud_api.dart';
import 'bfl_api.dart';
import 'fal_api.dart';
import 'krea_api.dart';
import 'ltx_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'runway_api.dart';
import 'package:http/http.dart' as http;

class ProviderApiRouter {
  ProviderApiRouter({
    ApipodApi? apipod,
    BflApi? bfl,
    LtxApi? ltx,
    ArtCraftApi? artcraft,
    AtlasCloudApi? atlas,
    RunwayApi? runway,
    KreaApi? krea,
    FalApi? fal,
    ComfyUiApi? comfyui,
  }) : apipod = apipod ?? ApipodApi(),
       bfl = bfl ?? BflApi(),
       ltx = ltx ?? LtxApi(),
       artcraft = artcraft ?? ArtCraftApi(),
       atlas = atlas ?? AtlasCloudApi(),
       runway = runway ?? RunwayApi(),
       krea = krea ?? KreaApi(),
       fal = fal ?? FalApi(),
       comfyui = comfyui ?? ComfyUiApi();

  final ApipodApi apipod;
  final BflApi bfl;
  final LtxApi ltx;
  final ArtCraftApi artcraft;
  final AtlasCloudApi atlas;
  final RunwayApi runway;
  final KreaApi krea;
  final FalApi fal;
  final ComfyUiApi comfyui;

  Future<ProviderAccountStatus> verifyConfiguration(
    String provider,
    Map<String, Object?> configuration,
  ) => switch (_adapter(provider)) {
    'comfyui' => comfyui.verify(ComfyUiSettings.fromJson(configuration)),
    _ => throw const ProviderException(
      'This provider does not accept workflow configuration.',
    ),
  };

  /// Provider-owned delivery routes may allow a private network address. All
  /// other providers continue through the gateway's public media policy.
  Future<http.StreamedResponse?> downloadResult(
    String provider,
    String source,
    String pollingUrl,
  ) async => providerByIdForRouting(provider)?.adapter == 'comfyui'
      ? comfyui.downloadResult(source, pollingUrl)
      : null;

  String? resultUrl(String provider, Object? result) =>
      _adapter(provider) == 'comfyui' && result is Map
      ? result['sample'] as String?
      : findResultUrl(result, draft: false);

  String _adapter(String provider) {
    final definition = providerByIdForRouting(provider);
    if (definition == null) {
      throw ProviderException('Provider "$provider" is not available.');
    }
    return definition.adapter;
  }

  Future<ProviderAccountStatus> verify(String provider, String key) async =>
      switch (_adapter(provider)) {
        'apipod' => apipod.verify(key),
        'ltx' => ltx.verify(key),
        'artcraft' => artcraft.verify(key),
        'atlas' => atlas.verify(key),
        'runway' => runway.verify(key),
        'krea' => krea.verify(key),
        'fal' => fal.verify(key),
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
    Map<String, Object?> configuration = const {},
  }) => switch (_adapter(provider)) {
    'comfyui' => comfyui.submit(
      ComfyUiSettings.fromJson(configuration),
      model,
      input,
      beforeSend: beforeSend,
    ),
    'apipod' => apipod.submit(
      key,
      model,
      input,
      beforeSend: beforeSend,
      operationId: operationId,
    ),
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
    'fal' => fal.submit(key, model, input, beforeSend: beforeSend),
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
    'comfyui' => comfyui.poll(pollingUrl),
    'apipod' => apipod.poll(key, pollingUrl),
    'ltx' => ltx.poll(key, pollingUrl),
    'artcraft' => artcraft.poll(key, pollingUrl),
    'atlas' => atlas.poll(key, pollingUrl),
    'runway' => runway.poll(key, pollingUrl),
    'krea' => krea.poll(key, pollingUrl),
    'fal' => fal.poll(key, pollingUrl),
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
        'fal' => fal.listVideoModels(key),
        'comfyui' ||
        'apipod' ||
        'bfl' ||
        'ltx' => Future<List<ProviderModelPrice>>.value(
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
    'apipod' => apipod.estimate(model, input),
    _ => Future<CostEstimate?>.value(),
  };
}
