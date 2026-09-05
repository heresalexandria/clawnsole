import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'bfl_api.dart';

typedef PublicMediaAddressLookup =
    Future<List<InternetAddress>> Function(String host);

/// Test seam for a single hop. Production always uses a pinned IO transport.
/// Implementations must disable redirects; [addresses] is an immutable list
/// of addresses already checked by the policy for [uri].
typedef PublicMediaTransportFactory =
    http.Client Function(
      Uri uri,
      List<InternetAddress> addresses,
      Duration connectTimeout,
    );

/// Streams untrusted remote media without allowing requests into local networks.
///
/// Every hop resolves once, rejects the entire DNS answer if any address is
/// unsafe, then connects to those exact addresses. TLS and HTTP retain the
/// original hostname. Proxies and automatic redirects are disabled so neither
/// can bypass the address policy. Never use this client for provider API calls:
/// only GET/HEAD and a small set of media headers are accepted.
///
/// A response's stream must be consumed or cancelled; [close] also aborts all
/// outstanding work. Header, idle, total-duration and decoded-byte limits apply
/// even to responses that omit Content-Length or use compression.
class PublicMediaClient extends http.BaseClient {
  PublicMediaClient({
    PublicMediaAddressLookup? addressLookup,
    PublicMediaTransportFactory? transportFactory,
    this.maxBytes = 2 * 1024 * 1024 * 1024,
    this.connectTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 20),
    this.totalTimeout = const Duration(minutes: 10),
    this.maxRedirects = 5,
  }) : _addressLookup = addressLookup ?? InternetAddress.lookup,
       _transportFactory = transportFactory ?? _pinnedTransport {
    if (maxBytes < 1 ||
        maxRedirects < 0 ||
        connectTimeout <= Duration.zero ||
        idleTimeout <= Duration.zero ||
        totalTimeout <= Duration.zero) {
      throw ArgumentError('Media limits must be positive.');
    }
  }

  final PublicMediaAddressLookup _addressLookup;
  final PublicMediaTransportFactory _transportFactory;
  final int maxBytes;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final Duration totalTimeout;
  final int maxRedirects;
  final Set<_MediaRequestScope> _active = <_MediaRequestScope>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw StateError('The media client is closed.');
    if (request.method != 'GET' && request.method != 'HEAD') {
      throw const ProviderException('Remote media only supports GET and HEAD.');
    }
    if ((request.contentLength ?? 0) != 0) {
      throw const ProviderException(
        'Remote media requests cannot have a body.',
      );
    }
    final headers = <String, String>{};
    for (final entry in request.headers.entries) {
      final name = entry.key.toLowerCase();
      if (!_mediaHeaders.contains(name)) {
        throw const ProviderException(
          'The remote media request has an unsafe header.',
        );
      }
      headers[name] = entry.value;
    }
    final scope = _MediaRequestScope(totalTimeout);
    _active.add(scope);
    scope.onFinish = () => _active.remove(scope);
    try {
      var uri = validatedProviderUrl(request.url.toString());
      for (var redirects = 0; ; redirects += 1) {
        final addresses = await scope.wait(
          _resolve(uri).timeout(connectTimeout),
        );
        scope.checkOpen();
        final transport = _transportFactory(uri, addresses, connectTimeout);
        scope.transport = transport;
        final hop = http.Request(request.method, uri)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..headers['accept-encoding'] = 'identity';
        final response = await scope.wait(
          transport.send(hop).timeout(connectTimeout),
        );
        scope.checkOpen();
        if (_redirectCodes.contains(response.statusCode)) {
          // Closing cancels the unused body instead of downloading an unbounded
          // redirect response before discovering that its target is unsafe.
          transport.close();
          scope.transport = null;
          if (redirects >= maxRedirects) {
            throw const ProviderException(
              'The remote media URL redirected too many times.',
            );
          }
          final location = response.headers['location'];
          if (location == null || location.isEmpty) {
            throw const ProviderException(
              'The remote media redirect is missing its destination.',
            );
          }
          uri = validatedProviderUrl(uri.resolve(location).toString());
          continue;
        }
        final responseHeaders = Map<String, String>.of(response.headers);
        var contentLength = response.contentLength;
        final encoding = responseHeaders['content-encoding']
            ?.trim()
            .toLowerCase();
        if (encoding != null && encoding.isNotEmpty && encoding != 'identity') {
          if (encoding != 'gzip' || response.statusCode == 206) {
            throw const ProviderException(
              'The remote media uses an unsupported content encoding.',
            );
          }
          // IOClient's HttpClient transparently expands gzip. The original
          // length describes compressed bytes and must not be compared with
          // or forwarded alongside the decoded stream. Range responses must
          // be identity encoded so Content-Range continues to describe bytes.
          responseHeaders.remove('content-encoding');
          responseHeaders.remove('content-length');
          contentLength = null;
        }
        if (request.method != 'HEAD' && (contentLength ?? 0) > maxBytes) {
          throw const ProviderException(
            'The remote media exceeds the download size limit.',
          );
        }
        return http.StreamedResponse(
          scope.boundStream(response.stream, maxBytes, idleTimeout),
          response.statusCode,
          contentLength: contentLength,
          headers: responseHeaders,
          isRedirect: response.isRedirect,
          persistentConnection: false,
          reasonPhrase: response.reasonPhrase,
          request: hop,
        );
      }
    } catch (_) {
      scope.finish();
      rethrow;
    }
  }

  Future<List<InternetAddress>> _resolve(Uri uri) =>
      _resolvePublicAddresses(uri, _addressLookup);

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final scope in _active.toList()) {
      scope.fail(StateError('The media client is closed.'));
    }
  }
}

const _redirectCodes = <int>{301, 302, 303, 307, 308};
const _mediaHeaders = <String>{
  'accept',
  'range',
  'if-range',
  'if-none-match',
  'if-modified-since',
};

/// Uses normalized address bytes rather than DNS labels or textual IP aliases.
bool isPublicMediaAddress(InternetAddress address) =>
    (address.type == InternetAddressType.IPv4 ||
        address.type == InternetAddressType.IPv6) &&
    isPublicProviderHost(address.address);

/// Checks the current DNS answer, but cannot secure a separate platform
/// transport's later DNS lookup or redirects. Use [PublicMediaClient] whenever
/// the process owns the connection; this preflight is for OS background work.
Future<void> validatePublicMediaDestination(
  Uri uri, {
  PublicMediaAddressLookup? addressLookup,
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _resolvePublicAddresses(
    validatedProviderUrl(uri.toString()),
    addressLookup ?? InternetAddress.lookup,
  ).timeout(timeout);
}

Future<List<InternetAddress>> _resolvePublicAddresses(
  Uri uri,
  PublicMediaAddressLookup lookup,
) async {
  final literal = InternetAddress.tryParse(uri.host);
  final addresses = literal == null
      ? await lookup(uri.host)
      : <InternetAddress>[literal];
  if (addresses.isEmpty ||
      addresses.any((address) => !isPublicMediaAddress(address))) {
    throw const ProviderException(
      'The remote media URL resolves to an unsafe network address.',
    );
  }
  return List<InternetAddress>.unmodifiable(addresses);
}

http.Client _pinnedTransport(
  Uri uri,
  List<InternetAddress> addresses,
  Duration timeout,
) {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (target, proxyHost, proxyPort) async {
    if (target.host != uri.host ||
        target.port != uri.port ||
        target.scheme != 'https' ||
        proxyHost != null ||
        proxyPort != null) {
      throw const ProviderException(
        'The remote media connection target changed.',
      );
    }
    return _connectPinned(addresses, target.host, target.port, timeout);
  };
  return IOClient(client);
}

/// No hostname reaches Socket: it cannot trigger a second DNS lookup. A failed
/// IPv6 route may fall back to another already validated address from the same
/// answer. The HttpClient still negotiates TLS for the original URI hostname.
ConnectionTask<Socket> _connectPinned(
  List<InternetAddress> addresses,
  String hostname,
  int port,
  Duration timeout,
) {
  ConnectionTask<Socket>? current;
  Socket? connected;
  var cancelled = false;
  Future<Socket> connect() async {
    Object? lastError;
    for (final address in addresses) {
      if (cancelled) throw const SocketException('Media connection cancelled.');
      try {
        current = await Socket.startConnect(address, port);
        if (cancelled) {
          current!.cancel();
          throw const SocketException('Media connection cancelled.');
        }
        connected = await current!.socket.timeout(
          timeout,
          onTimeout: () {
            current?.cancel();
            throw TimeoutException('The remote media connection timed out.');
          },
        );
        if (cancelled) {
          connected!.destroy();
          throw const SocketException('Media connection cancelled.');
        }
        // connectionFactory owns TLS too: preserve the original DNS hostname
        // for SNI and certificate validation while connecting to the pinned IP.
        final secure = await SecureSocket.secure(
          connected!,
          host: hostname,
        ).timeout(timeout);
        connected = secure;
        if (cancelled) {
          secure.destroy();
          throw const SocketException('Media connection cancelled.');
        }
        return secure;
      } catch (error) {
        connected?.destroy();
        connected = null;
        lastError = error;
      }
    }
    throw lastError ??
        const SocketException('No public media address is available.');
  }

  final socket = connect();
  // HttpClient first awaits the ConnectionTask factory, then subscribes to its
  // socket. Observe an immediate connect failure during that handoff as well;
  // the original future still delivers the same failure to HttpClient.
  unawaited(socket.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  return ConnectionTask.fromSocket(socket, () {
    cancelled = true;
    current?.cancel();
    connected?.destroy();
  });
}

class _MediaRequestScope {
  _MediaRequestScope(Duration totalTimeout) {
    _deadline = Timer(
      totalTimeout,
      () => fail(TimeoutException('The remote media download timed out.')),
    );
  }

  final Completer<Object> _aborted = Completer<Object>();
  late final Timer _deadline;
  http.Client? transport;
  void Function()? onFinish;
  void Function(Object)? _streamFailure;
  bool _finished = false;

  void checkOpen() {
    if (_finished) throw StateError('The media request is closed.');
  }

  Future<T> wait<T>(Future<T> future) => Future.any(<Future<T>>[
    future,
    _aborted.future.then<T>((error) => throw error),
  ]);

  void fail(Object error) {
    if (_finished) return;
    _aborted.complete(error);
    _streamFailure?.call(error);
    finish();
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    _deadline.cancel();
    transport?.close();
    transport = null;
    onFinish?.call();
  }

  Stream<List<int>> boundStream(
    Stream<List<int>> source,
    int maxBytes,
    Duration idleTimeout,
  ) {
    StreamSubscription<List<int>>? subscription;
    late final StreamController<List<int>> output;
    Timer? idle;
    var received = 0;
    void stop() {
      idle?.cancel();
      unawaited(subscription?.cancel());
      finish();
    }

    void failStream(Object error) {
      if (output.isClosed) return;
      output.addError(error);
      unawaited(output.close());
      stop();
    }

    void resetIdle() {
      idle?.cancel();
      idle = Timer(
        idleTimeout,
        () => fail(
          TimeoutException('The remote media download stopped responding.'),
        ),
      );
    }

    output = StreamController<List<int>>(
      onListen: () {
        if (_finished) return;
        resetIdle();
        subscription = source.listen(
          (chunk) {
            received += chunk.length;
            if (received > maxBytes) {
              fail(
                const ProviderException(
                  'The remote media exceeds the download size limit.',
                ),
              );
              return;
            }
            resetIdle();
            output.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (output.isClosed) return;
            output.addError(error, stack);
            unawaited(output.close());
            stop();
          },
          onDone: () {
            unawaited(output.close());
            stop();
          },
        );
      },
      onPause: () {
        idle?.cancel();
        subscription?.pause();
      },
      onResume: () {
        resetIdle();
        subscription?.resume();
      },
      onCancel: stop,
    );
    _streamFailure = failStream;
    return output.stream;
  }
}
