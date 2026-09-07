import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// What a recorded provider request was doing for its film.
enum ApiRequestPurpose {
  /// The chargeable POST that created the job.
  submit,

  /// A status check against the provider's polling URL.
  poll,

  /// An account/credit reading taken around a submit or a poll.
  balance,

  /// Fetching the finished film so it can be retained locally.
  result,

  /// Anything else an adapter did inside the operation's scope.
  other,
}

ApiRequestPurpose _purposeByName(Object? name) => ApiRequestPurpose.values
    .where((value) => value.name == name)
    .followedBy(const <ApiRequestPurpose>[ApiRequestPurpose.other])
    .first;

/// Everything the recorder will keep of one body.
const int maxRecordedRequestBodyBytes = 64 * 1024;
const int maxRecordedResponseBodyBytes = 256 * 1024;

/// A body longer than this is never buffered by the recorder, whatever it
/// claims to be: a transcript is worth far less than the memory of the
/// device rendering the film.
const int maxBufferedResponseBytes = 4 * 1024 * 1024;

/// How much of one film's transcript survives on disk.
const int maxApiRequestsPerFilm = 200;
const int maxApiTranscriptBytes = 4 * 1024 * 1024;

/// What replaces a secret. Chosen so a transcript can be pasted into an
/// issue and read as obviously scrubbed rather than as a real value.
const String redactedValue = '«redacted»';

/// Header names whose value never reaches the transcript.
const Set<String> _alwaysRedactedHeaders = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'api-key',
};

/// Substrings that make a header, query parameter, or JSON field a secret.
const List<String> _secretFragments = <String>[
  'key',
  'token',
  'secret',
  'password',
  'passwd',
  'credential',
  'signature',
  'authorization',
];

bool _looksSecret(String name) {
  final lower = name.toLowerCase();
  if (_alwaysRedactedHeaders.contains(lower)) return true;
  return _secretFragments.any(lower.contains);
}

String formatTranscriptBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes ${bytes == 1 ? 'byte' : 'bytes'}';
}

/// Whether a payload of [contentType] is text a director could read.
///
/// An event stream is text but is never finished, so it is deliberately not
/// one: the recorder must never wait on a body to describe it.
bool isTextualContentType(String? contentType) {
  final value = (contentType ?? '').toLowerCase();
  if (value.trim().isEmpty) return true;
  if (value.contains('event-stream')) return false;
  return value.startsWith('text/') ||
      value.contains('json') ||
      value.contains('xml') ||
      value.contains('yaml') ||
      value.contains('javascript') ||
      value.contains('x-www-form-urlencoded');
}

Map<String, String> redactHeaders(Map<String, String> headers) {
  final result = <String, String>{};
  for (final entry in headers.entries) {
    result[entry.key] = _looksSecret(entry.key) ? redactedValue : entry.value;
  }
  return result;
}

/// The URL as it may be shown: query values that name a credential are
/// scrubbed, because several providers still accept `?key=` style auth.
String redactUrl(Uri url) {
  if (url.query.isEmpty) return url.toString();
  // Rebuilt pair by pair from the raw query so untouched values keep their
  // original encoding and the marker itself is written as-is: a re-encoded
  // «redacted» reads as %C2%ABredacted%C2%BB in every row and copy.
  final pairs = <String>[
    for (final pair in url.query.split('&'))
      if (pair.isNotEmpty) _redactQueryPair(pair),
  ];
  final scrubbed = url.replace(query: '').toString();
  final base = scrubbed.endsWith('?')
      ? scrubbed.substring(0, scrubbed.length - 1)
      : scrubbed;
  final fragment = url.hasFragment ? '#${url.fragment}' : '';
  final withoutFragment = fragment.isEmpty
      ? base
      : base.substring(0, base.length - fragment.length);
  return '$withoutFragment?${pairs.join('&')}$fragment';
}

String _redactQueryPair(String pair) {
  final divider = pair.indexOf('=');
  final rawName = divider < 0 ? pair : pair.substring(0, divider);
  final name = Uri.decodeQueryComponent(rawName);
  if (!_looksSecret(name)) return pair;
  return '$rawName=$redactedValue';
}

final RegExp _base64Like = RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$');
final RegExp _dataUri = RegExp(r'^data:([^;,]*)[^,]*,');

/// The shortest string the recorder is willing to call a payload rather
/// than a sentence. Prompts are long; base64 frames are far longer.
const int _payloadStringLength = 256;

/// Replaces an inline media payload with what it was, and how big.
///
/// This is the rule that keeps AGENTS.md's compact-history promise true for
/// transcripts too: uploaded frames, video blobs, and base64 bodies are
/// described, never stored.
String? mediaPlaceholderFor(String value) {
  final match = _dataUri.firstMatch(value);
  if (match != null) {
    final mime = match.group(1)?.trim();
    final payload = value.substring(match.end);
    final bytes = (payload.length * 3) ~/ 4;
    final label = mime == null || mime.isEmpty ? 'data' : mime;
    return '«$label ${formatTranscriptBytes(bytes)}»';
  }
  if (value.length >= _payloadStringLength && _base64Like.hasMatch(value)) {
    return '«base64 ${formatTranscriptBytes((value.length * 3) ~/ 4)}»';
  }
  return null;
}

Object? _scrubJson(Object? value, {bool secret = false}) {
  if (secret && value is String) return redactedValue;
  if (value is String) return mediaPlaceholderFor(value) ?? value;
  if (value is List) {
    return value.map((child) => _scrubJson(child, secret: secret)).toList();
  }
  if (value is Map) {
    return value.map(
      (key, child) => MapEntry(
        key.toString(),
        _scrubJson(child, secret: secret || _looksSecret(key.toString())),
      ),
    );
  }
  return value;
}

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// Renders one body for the transcript: JSON pretty-printed with its media
/// and secrets replaced, anything else left as text.
String scrubBodyText(String body, {String? contentType}) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '';
  final looksJson =
      (contentType ?? '').toLowerCase().contains('json') ||
      trimmed.startsWith('{') ||
      trimmed.startsWith('[');
  if (looksJson) {
    try {
      return _prettyJson.convert(_scrubJson(jsonDecode(trimmed)));
    } on FormatException {
      // Not JSON after all; fall through to the plain-text path.
    }
  }
  return mediaPlaceholderFor(trimmed) ?? body;
}

/// A body cut to [limit], with how much was dropped.
typedef CappedBody = ({String text, int? truncatedBytes});

CappedBody capBody(String body, int limit) {
  final bytes = utf8.encode(body);
  if (bytes.length <= limit) return (text: body, truncatedBytes: null);
  final kept = utf8.decode(bytes.sublist(0, limit), allowMalformed: true);
  return (text: kept, truncatedBytes: bytes.length - limit);
}

/// One provider HTTP round trip, as it may be read and pasted.
///
/// Nothing here is a secret and nothing here is media: credentials are
/// replaced with [redactedValue] before the record exists, and binary
/// payloads are replaced with a size placeholder.
class ApiRequestRecord {
  const ApiRequestRecord({
    required this.id,
    required this.operationId,
    required this.at,
    required this.provider,
    required this.purpose,
    required this.method,
    required this.url,
    this.sequence = 0,
    this.durationMs = 0,
    this.requestHeaders = const <String, String>{},
    this.requestBody,
    this.requestTruncatedBytes,
    this.statusCode,
    this.responseHeaders = const <String, String>{},
    this.responseBody,
    this.responseTruncatedBytes,
    this.error,
  });

  factory ApiRequestRecord.fromJson(Map<String, Object?> json) {
    Map<String, String> headers(Object? value) => value is Map
        ? value.map((key, child) => MapEntry('$key', '${child ?? ''}'))
        : const <String, String>{};
    return ApiRequestRecord(
      id: '${json['id'] ?? ''}',
      operationId: '${json['operationId'] ?? ''}',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      at:
          DateTime.tryParse('${json['at']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      provider: '${json['provider'] ?? ''}',
      purpose: _purposeByName(json['purpose']),
      method: '${json['method'] ?? 'GET'}',
      url: '${json['url'] ?? ''}',
      requestHeaders: headers(json['requestHeaders']),
      requestBody: json['requestBody'] as String?,
      requestTruncatedBytes: (json['requestTruncatedBytes'] as num?)?.toInt(),
      statusCode: (json['statusCode'] as num?)?.toInt(),
      responseHeaders: headers(json['responseHeaders']),
      responseBody: json['responseBody'] as String?,
      responseTruncatedBytes: (json['responseTruncatedBytes'] as num?)?.toInt(),
      error: json['error'] as String?,
    );
  }

  final String id;

  /// The film's `localId`. One transcript belongs to one operation.
  final String operationId;

  /// 1-based position in this film's transcript, assigned when it is stored.
  final int sequence;
  final DateTime at;
  final int durationMs;
  final String provider;
  final ApiRequestPurpose purpose;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final int? requestTruncatedBytes;
  final int? statusCode;
  final Map<String, String> responseHeaders;
  final String? responseBody;
  final int? responseTruncatedBytes;

  /// A transport failure that produced no response at all.
  final String? error;

  ApiRequestRecord copyWith({int? sequence}) => ApiRequestRecord(
    id: id,
    operationId: operationId,
    sequence: sequence ?? this.sequence,
    at: at,
    durationMs: durationMs,
    provider: provider,
    purpose: purpose,
    method: method,
    url: url,
    requestHeaders: requestHeaders,
    requestBody: requestBody,
    requestTruncatedBytes: requestTruncatedBytes,
    statusCode: statusCode,
    responseHeaders: responseHeaders,
    responseBody: responseBody,
    responseTruncatedBytes: responseTruncatedBytes,
    error: error,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'operationId': operationId,
    'sequence': sequence,
    'at': at.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'provider': provider,
    'purpose': purpose.name,
    'method': method,
    'url': url,
    'requestHeaders': requestHeaders,
    if (requestBody != null) 'requestBody': requestBody,
    if (requestTruncatedBytes != null)
      'requestTruncatedBytes': requestTruncatedBytes,
    if (statusCode != null) 'statusCode': statusCode,
    'responseHeaders': responseHeaders,
    if (responseBody != null) 'responseBody': responseBody,
    if (responseTruncatedBytes != null)
      'responseTruncatedBytes': responseTruncatedBytes,
    if (error != null) 'error': error,
  };

  /// The path (and query) alone, for the collapsed row.
  String get shortUrl {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    final query = parsed.query.isEmpty ? '' : '?${parsed.query}';
    return '${parsed.path.isEmpty ? '/' : parsed.path}$query';
  }

  String get statusLabel => error != null
      ? 'failed'
      : statusCode == null
      ? '—'
      : '$statusCode';

  bool get succeeded =>
      error == null &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 300;

  /// A readable plain-text block for one request. This is what a copy
  /// button puts on the clipboard, so it has to stand alone.
  String toTranscriptText() {
    final buffer = StringBuffer()
      ..writeln('── #$sequence · ${purpose.name} · $provider')
      ..writeln('at        ${at.toUtc().toIso8601String()}')
      ..writeln('duration  $durationMs ms')
      ..writeln('request   $method $url');
    _writeHeaders(buffer, requestHeaders);
    _writeBody(buffer, requestBody, requestTruncatedBytes);
    if (error != null) {
      buffer.writeln('response  transport error');
      buffer.writeln('  $error');
      return buffer.toString();
    }
    buffer.writeln('response  ${statusCode ?? '—'}');
    _writeHeaders(buffer, responseHeaders);
    _writeBody(buffer, responseBody, responseTruncatedBytes);
    return buffer.toString();
  }

  static void _writeHeaders(StringBuffer buffer, Map<String, String> headers) {
    if (headers.isEmpty) return;
    buffer.writeln('headers');
    final names = headers.keys.toList()..sort();
    for (final name in names) {
      buffer.writeln('  $name: ${headers[name]}');
    }
  }

  static void _writeBody(StringBuffer buffer, String? body, int? truncated) {
    final value = body?.trim() ?? '';
    buffer.writeln('body');
    if (value.isEmpty) {
      buffer.writeln('  (none)');
    } else {
      for (final line in value.split('\n')) {
        buffer.writeln('  $line');
      }
    }
    if (truncated != null) {
      buffer.writeln(
        '  … truncated · ${formatTranscriptBytes(truncated)} more was '
        'not kept',
      );
    }
  }
}

/// The whole transcript as one paste-ready block.
///
/// The header names the film so a pasted transcript still says what it is
/// about, and the note says what was removed so nobody hunts for a payload
/// that was never kept.
String renderTranscript(List<ApiRequestRecord> records, {Generation? film}) {
  final buffer = StringBuffer('Clawnsole API transcript\n');
  if (film != null) {
    buffer
      ..writeln('film      ${film.localId}')
      ..writeln('provider  ${film.provider} · ${film.model}')
      ..writeln('created   ${film.createdAt.toUtc().toIso8601String()}')
      ..writeln('status    ${film.status}');
    if (film.requestId != null) buffer.writeln('requestId ${film.requestId}');
  }
  buffer
    ..writeln('requests  ${records.length}')
    ..writeln(
      'note      Credentials are redacted; uploaded media and base64 '
      'payloads are replaced by size placeholders.',
    );
  for (final record in records) {
    buffer
      ..writeln()
      ..write(record.toTranscriptText());
  }
  return buffer.toString();
}

/// Where finished records go. Implementations must not make the caller wait
/// and must never let a storage failure reach the provider call.
abstract interface class ApiTranscriptSink {
  void addApiRequest(ApiRequestRecord record);
}

/// The operation a provider call belongs to, carried in the zone.
///
/// The adapters interleave awaits, retries, and `Future.wait` fan-outs, and
/// several films poll at once, so a mutable field on the client would tag
/// records with whichever operation last touched it. A zone value is copied
/// into every asynchronous continuation started inside it, so a record is
/// attributed to the operation whose call actually started it, however deep
/// the adapter's async flow goes and however many operations overlap.
class ApiTranscriptScope {
  const ApiTranscriptScope({
    required this.sink,
    required this.operationId,
    required this.provider,
    required this.purpose,
  });

  final ApiTranscriptSink sink;
  final String operationId;
  final String provider;
  final ApiRequestPurpose purpose;

  static const Object _zoneKey = #clawnsoleApiTranscript;

  /// The scope a provider call is running inside, if any. Calls made outside
  /// one — key verification, model listings, media the library asks for —
  /// belong to no film and are never recorded.
  static ApiTranscriptScope? get current {
    final value = Zone.current[_zoneKey];
    return value is ApiTranscriptScope ? value : null;
  }

  /// Runs [body] with every HTTP call an adapter makes recorded against
  /// [operationId]. A null [sink] simply runs [body] unrecorded.
  static Future<T> run<T>(
    Future<T> Function() body, {
    required ApiTranscriptSink? sink,
    required String operationId,
    required String provider,
    required ApiRequestPurpose purpose,
  }) {
    if (sink == null || operationId.isEmpty) return body();
    return runZoned(
      body,
      zoneValues: <Object, Object?>{
        _zoneKey: ApiTranscriptScope(
          sink: sink,
          operationId: operationId,
          provider: provider,
          purpose: purpose,
        ),
      },
    );
  }

  /// Re-labels the calls [body] makes — a balance reading taken in the
  /// middle of a submit is still that submit's operation, but it is not the
  /// submit.
  static Future<T> runPurpose<T>(
    Future<T> Function() body,
    ApiRequestPurpose purpose,
  ) {
    final scope = current;
    if (scope == null || scope.purpose == purpose) return body();
    return runZoned(
      body,
      zoneValues: <Object, Object?>{
        _zoneKey: ApiTranscriptScope(
          sink: scope.sink,
          operationId: scope.operationId,
          provider: scope.provider,
          purpose: purpose,
        ),
      },
    );
  }
}

int _recordCounter = 0;

String _recordId() {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  return '$stamp-${(_recordCounter++).toRadixString(16)}';
}

/// Wraps [inner] so every call an adapter makes inside an
/// [ApiTranscriptScope] is recorded. Outside a scope it is a pass-through.
///
/// Adapters wrap their client once at construction, which covers every one
/// of their calls — including ones added later — without a single call site
/// knowing that transcripts exist.
http.Client recordingProviderClient(http.Client inner) =>
    inner is RecordingHttpClient ? inner : RecordingHttpClient(inner);

class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final scope = ApiTranscriptScope.current;
    if (scope == null) return _inner.send(request);
    final started = DateTime.now();
    final captured = _captureRequest(request);
    try {
      final response = await _inner.send(request);
      final body = await _captureResponse(response);
      scope.sink.addApiRequest(
        ApiRequestRecord(
          id: _recordId(),
          operationId: scope.operationId,
          at: started.toUtc(),
          durationMs: DateTime.now().difference(started).inMilliseconds,
          provider: scope.provider,
          purpose: scope.purpose,
          method: request.method,
          url: redactUrl(request.url),
          requestHeaders: redactHeaders(request.headers),
          requestBody: captured.text,
          requestTruncatedBytes: captured.truncatedBytes,
          statusCode: response.statusCode,
          responseHeaders: redactHeaders(response.headers),
          responseBody: body.captured.text,
          responseTruncatedBytes: body.captured.truncatedBytes,
        ),
      );
      return body.response;
    } on Object catch (error) {
      scope.sink.addApiRequest(
        ApiRequestRecord(
          id: _recordId(),
          operationId: scope.operationId,
          at: started.toUtc(),
          durationMs: DateTime.now().difference(started).inMilliseconds,
          provider: scope.provider,
          purpose: scope.purpose,
          method: request.method,
          url: redactUrl(request.url),
          requestHeaders: redactHeaders(request.headers),
          requestBody: captured.text,
          requestTruncatedBytes: captured.truncatedBytes,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Reads what a request is about to send without consuming anything the
  /// client still needs. Multipart uploads are described part by part, so a
  /// frame becomes its size rather than its bytes.
  static CappedBody _captureRequest(http.BaseRequest request) {
    final contentType = request.headers['content-type'];
    if (request is http.MultipartRequest) {
      final buffer = StringBuffer('«multipart/form-data»');
      for (final entry in request.fields.entries) {
        final value = _looksSecret(entry.key)
            ? redactedValue
            : scrubBodyText(entry.value);
        buffer.write('\nfield ${entry.key} = $value');
      }
      for (final file in request.files) {
        final type = file.contentType.toString();
        buffer.write(
          '\nfile ${file.field} = ${file.filename ?? '(unnamed)'} '
          '«$type ${formatTranscriptBytes(file.length)}»',
        );
      }
      return capBody(buffer.toString(), maxRecordedRequestBodyBytes);
    }
    if (request is http.Request) {
      if (request.bodyBytes.isEmpty) return (text: '', truncatedBytes: null);
      if (!isTextualContentType(contentType)) {
        return (
          text:
              '«${contentType ?? 'binary'} '
              '${formatTranscriptBytes(request.bodyBytes.length)}»',
          truncatedBytes: null,
        );
      }
      String raw;
      try {
        raw = request.body;
      } on Object {
        return (
          text: '«binary ${formatTranscriptBytes(request.bodyBytes.length)}»',
          truncatedBytes: null,
        );
      }
      return capBody(
        scrubBodyText(raw, contentType: contentType),
        maxRecordedRequestBodyBytes,
      );
    }
    final length = request.contentLength;
    return (
      text: length == null || length == 0
          ? ''
          : '«streamed ${formatTranscriptBytes(length)}»',
      truncatedBytes: null,
    );
  }

  /// Buffers a readable response so it can be both recorded and returned;
  /// media is described from its headers and its stream is handed on
  /// untouched, so a film's bytes never pass through the transcript.
  ///
  /// Only a body the caller was already going to hold in memory is buffered
  /// — a JSON receipt or an error page — so recording never changes what a
  /// download costs.
  static Future<({http.StreamedResponse response, CappedBody captured})>
  _captureResponse(http.StreamedResponse response) async {
    final contentType = response.headers['content-type'];
    final length = response.contentLength;
    final unreadable =
        !isTextualContentType(contentType) ||
        (length != null && length > maxBufferedResponseBytes);
    if (unreadable) {
      return (
        response: response,
        captured: (
          text:
              '«${contentType ?? 'binary'}'
              '${length == null ? '' : ' ${formatTranscriptBytes(length)}'}»',
          truncatedBytes: null,
        ),
      );
    }
    final bytes = await response.stream.toBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return (
      response: http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      ),
      captured: capBody(
        scrubBodyText(text, contentType: contentType),
        maxRecordedResponseBodyBytes,
      ),
    );
  }
}
