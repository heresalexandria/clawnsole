import 'dart:async';

/// Releases a stream this caller has decided not to read.
///
/// A discarded stream can still fail after the reader gives up on it: an
/// aborted media client, a closed socket, or a cancelled transfer all deliver
/// a late error to whoever is still subscribed. `listen(null)` leaves no error
/// handler, so that error reaches the zone and terminates the process — in the
/// companion, an abandoned download would take the whole desktop session down
/// with it. Discarding must be quiet, and so must a cancellation that fails
/// because the source is already broken.
Future<void> discardStream(Stream<Object?> stream) async {
  try {
    await stream
        .listen(null, onError: (Object _, StackTrace _) {}, cancelOnError: true)
        .cancel();
  } on Object {
    // The source failed while being released; the caller is discarding it.
  }
}
