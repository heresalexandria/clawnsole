part of 'app_controller.dart';

/// The per-film API transcript: what a card's ⋯ menu reads and copies.
///
/// Transcripts are recorded by whichever surface actually made the provider
/// calls — the app itself on native, the companion beside the renderer on
/// desktop — and they never leave that device. A film opened somewhere else
/// simply has none, which the modal says out loud rather than implying the
/// calls were never made.
extension ApiTranscriptController on AppController {
  /// Whether this build can read transcripts at all.
  bool get canReadApiRequests => gateway is ApiTranscriptGateway;

  /// Every provider request recorded for [item] on this device, oldest
  /// first. A gateway that keeps none answers with an empty list rather
  /// than an error: nothing recorded is a real, ordinary answer.
  Future<List<ApiRequestRecord>> apiRequestsFor(Generation item) async {
    final target = gateway;
    if (target is! ApiTranscriptGateway) return const <ApiRequestRecord>[];
    try {
      return await (target as ApiTranscriptGateway).readApiRequests(
        item.localId,
      );
    } on Object {
      return const <ApiRequestRecord>[];
    }
  }

  /// The whole transcript as one paste-ready block, film header included.
  Future<String> apiTranscriptFor(Generation item) async =>
      renderTranscript(await apiRequestsFor(item), film: item);
}
