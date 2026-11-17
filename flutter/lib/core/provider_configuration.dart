import 'comfyui_settings.dart';
import 'provider_catalog.dart';

/// Provider-owned configuration schemas behind a neutral application contract.
/// Unknown saved configurations are preserved for forward compatibility.
void validateProviderConfiguration(
  String provider,
  Map<String, Object?> value,
) {
  if (providerByIdForRouting(provider)?.adapter == 'comfyui') {
    ComfyUiSettings.fromJson(value).validate();
  }
}

bool providerConfigurationReady(String provider, Map<String, Object?>? value) {
  if (value == null) return false;
  try {
    validateProviderConfiguration(provider, value);
    return true;
  } on Object {
    return false;
  }
}

Set<String> configuredProviderModels(
  String provider,
  Map<String, Object?>? value,
) {
  if (!providerConfigurationReady(provider, value)) return const {};
  return switch (providerByIdForRouting(provider)?.adapter) {
    'comfyui' => ComfyUiSettings.fromJson(value).workflows.keys.toSet(),
    _ => const {},
  };
}
