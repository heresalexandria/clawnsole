import 'artcraft_api.dart';
import 'atlas_cloud_api.dart';
import 'bfl_api.dart';
import 'ltx_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

class ProviderApiRouter {
  ProviderApiRouter({
    BflApi? bfl,
    LtxApi? ltx,
    ArtCraftApi? artcraft,
    AtlasCloudApi? atlas,
  }) : bfl = bfl ?? BflApi(),
       ltx = ltx ?? LtxApi(),
       artcraft = artcraft ?? ArtCraftApi(),
       atlas = atlas ?? AtlasCloudApi();

  final BflApi bfl;
  final LtxApi ltx;
  final ArtCraftApi artcraft;
  final AtlasCloudApi atlas;

  Future<ProviderAccountStatus> verify(String provider, String key) async =>
      switch (provider) {
        'ltx' => ltx.verify(key),
        'artcraft' => artcraft.verify(key),
        'atlas' => atlas.verify(key),
        _ => ProviderAccountStatus(
          provider: 'bfl',
          balance: await bfl.getCredits(key),
          currency: 'credits',
        ),
      };

  Future<Map<String, Object?>> submit(
    String provider,
    String key,
    String model,
    Map<String, Object?> input,
  ) => switch (provider) {
    'ltx' => ltx.submit(key, model, input),
    'artcraft' => artcraft.submit(key, model, input),
    'atlas' => atlas.submit(key, model, input),
    _ => bfl.submit(key, input, model: model),
  };

  Future<Map<String, Object?>> poll(
    String provider,
    String key,
    String pollingUrl,
  ) => switch (provider) {
    'ltx' => ltx.poll(key, pollingUrl),
    'artcraft' => artcraft.poll(key, pollingUrl),
    'atlas' => atlas.poll(key, pollingUrl),
    _ => bfl.poll(key, pollingUrl),
  };

  Future<List<ProviderModelPrice>> listModels(String provider, [String? key]) =>
      switch (provider) {
        'atlas' => atlas.listVideoModels(key),
        'artcraft' => artcraft.listVideoModels(),
        _ => Future<List<ProviderModelPrice>>.value(
          publishedProviderPrices(provider),
        ),
      };

  Future<CostEstimate?> quote(
    String provider,
    String model,
    Map<String, Object?> input,
  ) => switch (provider) {
    'artcraft' => artcraft.estimate(model, input),
    _ => Future<CostEstimate?>.value(),
  };
}
