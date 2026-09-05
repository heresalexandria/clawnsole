import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bfl_api.dart';

/// Called after uploads/validation, immediately before a chargeable POST.
/// A failure must prevent the POST: durable intent precedes the network side
/// effect, so a restart never incorrectly declares that it was rejected.
typedef BeforeGenerationSend = Future<void> Function();

/// UUIDv5 in a Clawnsole operation namespace. The input is a generation's
/// unique local ID, never its prompt or media: intentional identical renders
/// are separate operations while recovery keeps the same provider token.
String submissionIdempotencyToken(String operationId) {
  const namespace = <int>[
    0x66,
    0xda,
    0xe8,
    0x88,
    0x42,
    0x64,
    0x58,
    0x89,
    0xba,
    0x6d,
    0x79,
    0xed,
    0xd7,
    0x9b,
    0xec,
    0x3a,
  ];
  final bytes = sha1
      .convert([...namespace, ...utf8.encode(operationId)])
      .bytes
      .take(16)
      .toList();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A timeout (408), conflict (409), transport failure, malformed receipt or
/// server failure cannot prove that a provider did not enqueue the job.
bool isDefinitiveSubmissionRejection(Object error) =>
    error is ProviderException &&
    const {
      400,
      401,
      402,
      403,
      404,
      405,
      413,
      415,
      422,
      429,
    }.contains(error.status);
