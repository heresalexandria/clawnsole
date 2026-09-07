import 'api_transcript.dart';
import 'durable_data_store.dart';
import 'models.dart';

/// Per-film API transcripts, kept beside the library rather than inside it.
///
/// This is an optional capability, like [StreamingAssetStore]: a store that
/// cannot keep transcripts (the web stub, small test stores) simply does not
/// implement it and the extension below turns every call into a no-op.
///
/// Transcripts never enter `clawnsole.json` and never reach Google Drive.
/// They are debugging exhaust of the device that made the calls, they can be
/// large, and only that device can honestly claim to have made them.
abstract interface class ApiTranscriptStore {
  /// Appends [record], assigning it the next sequence for its operation.
  Future<void> appendApiRequest(ApiRequestRecord record);

  /// Every record kept for [operationId], oldest first.
  Future<List<ApiRequestRecord>> readApiRequests(String operationId);

  /// Forgets one film's transcript.
  Future<void> deleteApiRequests(String operationId);

  /// Drops transcripts no surviving film can explain. [retainedOperationIds]
  /// is the library's own list of films, so this is the same reference-aware
  /// cleanup that prunes assets.
  Future<void> pruneApiTranscripts(Set<String> retainedOperationIds);
}

/// The transcript surface every [DurableDataStore] answers to, whether or
/// not it can actually keep one.
extension DurableApiTranscripts on DurableDataStore {
  ApiTranscriptStore? get _transcripts {
    final target = this;
    return target is ApiTranscriptStore ? target as ApiTranscriptStore : null;
  }

  bool get keepsApiTranscripts => _transcripts != null;

  Future<void> appendApiRequest(ApiRequestRecord record) async =>
      _transcripts?.appendApiRequest(record);

  Future<List<ApiRequestRecord>> readApiRequests(String operationId) async =>
      await _transcripts?.readApiRequests(operationId) ??
      const <ApiRequestRecord>[];

  Future<void> deleteApiRequests(String operationId) async =>
      _transcripts?.deleteApiRequests(operationId);

  Future<void> pruneApiTranscripts(Set<String> retainedOperationIds) async =>
      _transcripts?.pruneApiTranscripts(retainedOperationIds);
}

/// Serializes appends and swallows storage failures.
///
/// A transcript is a convenience; a film is not. Nothing here may delay a
/// provider call or fail one, so records queue behind each other and a
/// broken disk quietly stops recording.
class QueuedApiTranscriptSink implements ApiTranscriptSink {
  QueuedApiTranscriptSink(this._append);

  /// The sink a [DurableDataStore] backs. Stores without the transcript
  /// capability accept records and drop them.
  QueuedApiTranscriptSink.forStore(DurableDataStore store)
    : _append = store.appendApiRequest;

  final Future<void> Function(ApiRequestRecord record) _append;
  Future<void> _tail = Future<void>.value();

  @override
  void addApiRequest(ApiRequestRecord record) {
    _tail = _tail
        .then((_) => _append(record))
        .catchError((Object _, StackTrace __) {});
  }

  /// Waits for queued appends. Tests and shutdown use this; the recorder's
  /// callers never do.
  Future<void> get settled => _tail;
}

/// The films whose transcripts are worth keeping.
Set<String> retainedTranscriptIds(List<Generation> generations) =>
    generations.map((item) => item.localId).toSet();
