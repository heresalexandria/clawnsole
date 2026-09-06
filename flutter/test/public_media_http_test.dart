import 'dart:async';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/public_media_http_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _public = InternetAddress('93.184.216.34');
final _url = Uri.parse('https://media.example.com/video.mp4?signature=keep');

void main() {
  test(
    'DNS answers reject private and mixed public/private addresses before send',
    () async {
      for (final answer in <List<InternetAddress>>[
        <InternetAddress>[],
        <InternetAddress>[InternetAddress('127.0.0.1')],
        <InternetAddress>[InternetAddress('10.2.3.4')],
        <InternetAddress>[InternetAddress('169.254.169.254')],
        <InternetAddress>[InternetAddress('0:0:0:0:0:ffff:7f00:1')],
        <InternetAddress>[_public, InternetAddress('192.168.1.2')],
      ]) {
        var sends = 0;
        final client = PublicMediaClient(
          addressLookup: (_) async => answer,
          transportFactory: (_, _, _) {
            sends += 1;
            throw StateError('Must not send');
          },
        );
        addTearDown(client.close);
        await expectLater(client.get(_url), throwsA(isA<ProviderException>()));
        expect(sends, 0);
      }
    },
  );

  test(
    'public CDN redirects preserve signed URLs and Range without cookies',
    () async {
      final transports = <_Transport>[];
      final lookedUp = <String>[];
      final requests = <http.BaseRequest>[];
      final client = PublicMediaClient(
        addressLookup: (host) async {
          lookedUp.add(host);
          return <InternetAddress>[_public];
        },
        transportFactory: (uri, addresses, timeout) {
          expect(addresses.single.address, _public.address);
          expect(() => addresses.clear(), throwsUnsupportedError);
          final transport = _Transport((request) async {
            requests.add(request);
            expect(request.followRedirects, isFalse);
            expect(request.headers['range'], 'bytes=20-29');
            expect(request.headers['if-range'], 'etag-value');
            if (transports.length == 1) {
              return http.StreamedResponse(
                const Stream.empty(),
                307,
                headers: <String, String>{
                  'location':
                      'https://cdn.example.net/file?token=signed%2Bvalue',
                  'set-cookie': 'private=do-not-forward',
                },
              );
            }
            return http.StreamedResponse(
              Stream.value(<int>[1, 2, 3]),
              206,
              headers: <String, String>{'content-range': 'bytes 20-22/100'},
            );
          });
          transports.add(transport);
          return transport;
        },
      );
      addTearDown(client.close);
      final response = await client.get(
        _url,
        headers: <String, String>{
          'Range': 'bytes=20-29',
          'If-Range': 'etag-value',
        },
      );
      expect(response.statusCode, 206);
      expect(response.bodyBytes, <int>[1, 2, 3]);
      expect(response.headers['content-range'], 'bytes 20-22/100');
      expect(lookedUp, <String>['media.example.com', 'cdn.example.net']);
      expect(requests.last.url.query, 'token=signed%2Bvalue');
      expect(requests.last.headers.containsKey('cookie'), isFalse);
      expect(transports.every((transport) => transport.closed), isTrue);
    },
  );

  test(
    'redirects reject private DNS, literal, userinfo and HTTPS downgrade targets',
    () async {
      for (final target in <String>[
        'https://private.example.com/file',
        'https://127.0.0.1/file',
        'https://user:password@cdn.example.com/file',
        'http://cdn.example.com/file',
      ]) {
        var sends = 0;
        late _Transport transport;
        final client = PublicMediaClient(
          addressLookup: (host) async => <InternetAddress>[
            host == 'private.example.com'
                ? InternetAddress('10.1.2.3')
                : _public,
          ],
          transportFactory: (_, _, _) => transport = _Transport((_) async {
            sends += 1;
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: <String, String>{'location': target},
            );
          }),
        );
        addTearDown(client.close);
        await expectLater(client.get(_url), throwsA(isA<ProviderException>()));
        expect(sends, 1);
        expect(transport.closed, isTrue);
      }
    },
  );

  test(
    'same-host redirect resolves again and rejects a rebound private answer',
    () async {
      var lookups = 0;
      var sends = 0;
      final client = PublicMediaClient(
        addressLookup: (_) async => <InternetAddress>[
          lookups++ == 0 ? _public : InternetAddress('127.0.0.1'),
        ],
        transportFactory: (_, _, _) => _Transport((_) async {
          sends += 1;
          return http.StreamedResponse(
            const Stream.empty(),
            302,
            headers: <String, String>{'location': '/changed'},
          );
        }),
      );
      addTearDown(client.close);
      await expectLater(client.get(_url), throwsA(isA<ProviderException>()));
      expect(lookups, 2);
      expect(sends, 1);
    },
  );

  test(
    'production socket receives a validated IP instead of resolving the hostname again',
    () async {
      var lookups = 0;
      final socketHosts = <Object>[];
      final client = PublicMediaClient(
        addressLookup: (_) async {
          lookups += 1;
          // A second DNS query would be an unsafe rebinding opportunity.
          return <InternetAddress>[
            lookups == 1 ? _public : InternetAddress('127.0.0.1'),
          ];
        },
      );
      addTearDown(client.close);
      await IOOverrides.runZoned(
        () async {
          await expectLater(
            client.get(_url),
            throwsA(isA<http.ClientException>()),
          );
        },
        socketStartConnect:
            (host, port, {sourceAddress, sourcePort = 0}) async {
              socketHosts.add(host as Object);
              expect(port, 443);
              throw const SocketException(
                'Synthetic socket stop before network',
              );
            },
      );
      expect(lookups, 1);
      expect(socketHosts.single, isA<InternetAddress>());
      expect((socketHosts.single as InternetAddress).address, _public.address);
    },
  );

  test(
    'literal global IPv6 is accepted without DNS and special IPv6 ranges are refused',
    () async {
      final client = PublicMediaClient(
        addressLookup: (_) => throw StateError('Literal must not resolve'),
        transportFactory: (_, addresses, _) {
          expect(addresses.single.address, '2606:4700:4700::1111');
          return _Transport(
            (_) async => http.StreamedResponse(const Stream.empty(), 200),
          );
        },
      );
      addTearDown(client.close);
      expect(
        (await client.get(
          Uri.parse('https://[2606:4700:4700::1111]/'),
        )).statusCode,
        200,
      );
      for (final address in <String>[
        '2001:db8::1',
        '2002:7f00:1::1',
        '64:ff9b::7f00:1',
        '3fff::1',
        '0:0:0:0:0:0:0:1',
        'ff02::1',
        'fec0::1',
      ]) {
        expect(
          isPublicMediaAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
    },
  );

  test(
    'redirect loops have a finite hop budget and close every response',
    () async {
      final transports = <_Transport>[];
      final client = PublicMediaClient(
        maxRedirects: 2,
        addressLookup: (_) async => <InternetAddress>[_public],
        transportFactory: (_, _, _) {
          final transport = _Transport(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              301,
              headers: <String, String>{'location': '/again'},
            ),
          );
          transports.add(transport);
          return transport;
        },
      );
      addTearDown(client.close);
      await expectLater(client.get(_url), throwsA(isA<ProviderException>()));
      expect(transports.length, 3);
      expect(transports.every((transport) => transport.closed), isTrue);
    },
  );

  test('credential headers and bodies are rejected before DNS', () async {
    final client = PublicMediaClient(
      addressLookup: (_) => throw StateError('Must not resolve'),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(_url, headers: <String, String>{'Authorization': 'secret'}),
      throwsA(isA<ProviderException>()),
    );
    await expectLater(
      client.send(http.Request('POST', _url)),
      throwsA(isA<ProviderException>()),
    );
    await expectLater(
      client.send(http.Request('GET', _url)..body = 'unexpected'),
      throwsA(isA<ProviderException>()),
    );
  });

  test('declared and streamed size limits both close the connection', () async {
    for (final declared in <int?>[10, null]) {
      late _Transport transport;
      final client = PublicMediaClient(
        maxBytes: 4,
        addressLookup: (_) async => <InternetAddress>[_public],
        transportFactory: (_, _, _) => transport = _Transport(
          (_) async => http.StreamedResponse(
            Stream.fromIterable(<List<int>>[
              <int>[1, 2, 3],
              <int>[4, 5],
            ]),
            200,
            contentLength: declared,
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(client.get(_url), throwsA(isA<ProviderException>()));
      expect(transport.closed, isTrue);
    }
  });

  test('idle stream deadline cancels an unresponsive body', () async {
    final source = StreamController<List<int>>();
    late _Transport transport;
    final client = PublicMediaClient(
      idleTimeout: const Duration(milliseconds: 20),
      addressLookup: (_) async => <InternetAddress>[_public],
      transportFactory: (_, _, _) => transport = _Transport(
        (_) async => http.StreamedResponse(source.stream, 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(client.get(_url), throwsA(isA<TimeoutException>()));
    expect(transport.closed, isTrue);
    expect(source.hasListener, isFalse);
    await source.close();
  });

  test(
    'decoded gzip drops encoded length and preserves streaming byte limits',
    () async {
      for (final limit in <int>[4, 20]) {
        late _Transport transport;
        final client = PublicMediaClient(
          maxBytes: limit,
          addressLookup: (_) async => <InternetAddress>[_public],
          transportFactory: (_, _, _) => transport = _Transport((
            request,
          ) async {
            expect(request.headers['accept-encoding'], 'identity');
            // This seam stands in for IOClient, which has already decoded gzip.
            return http.StreamedResponse(
              Stream.value(List<int>.filled(10, 1)),
              200,
              contentLength: 3,
              headers: <String, String>{
                'content-length': '3',
                'content-encoding': 'gzip',
              },
            );
          }),
        );
        addTearDown(client.close);
        final response = await client.send(http.Request('GET', _url));
        expect(response.contentLength, isNull);
        expect(response.headers.containsKey('content-length'), isFalse);
        expect(response.headers.containsKey('content-encoding'), isFalse);
        if (limit == 4) {
          await expectLater(
            response.stream.drain<void>(),
            throwsA(isA<ProviderException>()),
          );
        } else {
          expect(await response.stream.toBytes(), hasLength(10));
        }
        expect(transport.closed, isTrue);
      }
    },
  );

  test(
    'encoded Range responses are refused before returning a mismatched range',
    () async {
      final client = PublicMediaClient(
        addressLookup: (_) async => <InternetAddress>[_public],
        transportFactory: (_, _, _) => _Transport(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            206,
            headers: <String, String>{
              'content-encoding': 'gzip',
              'content-range': 'bytes 0-9/100',
            },
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(_url, headers: <String, String>{'Range': 'bytes=0-9'}),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test('total deadline covers DNS and closes an abandoned response', () async {
    final stalled = PublicMediaClient(
      totalTimeout: const Duration(milliseconds: 20),
      addressLookup: (_) => Completer<List<InternetAddress>>().future,
    );
    addTearDown(stalled.close);
    await expectLater(stalled.get(_url), throwsA(isA<TimeoutException>()));
    late _Transport transport;
    final client = PublicMediaClient(
      totalTimeout: const Duration(milliseconds: 20),
      addressLookup: (_) async => <InternetAddress>[_public],
      transportFactory: (_, _, _) => transport = _Transport(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      ),
    );
    addTearDown(client.close);
    final response = await client.send(http.Request('GET', _url));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(transport.closed, isTrue);
    await expectLater(
      response.stream.drain<void>(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'stream cancellation and explicit client close release active transports',
    () async {
      for (final explicitClose in <bool>[false, true]) {
        final source = StreamController<List<int>>();
        late _Transport transport;
        final client = PublicMediaClient(
          addressLookup: (_) async => <InternetAddress>[_public],
          transportFactory: (_, _, _) => transport = _Transport(
            (_) async => http.StreamedResponse(source.stream, 200),
          ),
        );
        addTearDown(client.close);
        final response = await client.send(http.Request('GET', _url));
        final errors = <Object>[];
        final subscription = response.stream.listen(
          (_) {},
          onError: errors.add,
        );
        if (explicitClose) {
          client.close();
          await Future<void>.delayed(Duration.zero);
          expect(errors.single, isA<StateError>());
        } else {
          await subscription.cancel();
        }
        expect(transport.closed, isTrue);
        expect(source.hasListener, isFalse);
        await source.close();
      }
    },
  );

  test('an abort carries a stack trace to whoever is still reading', () async {
    // A StateError that is signalled rather than thrown carries no stack of
    // its own, so an abort that surfaces through an abandoned stream would be
    // logged as a bare line naming neither the request nor the caller that
    // closed the client.
    final source = StreamController<List<int>>();
    final client = PublicMediaClient(
      addressLookup: (_) async => <InternetAddress>[_public],
      transportFactory: (_, _, _) =>
          _Transport((_) async => http.StreamedResponse(source.stream, 200)),
    );
    final response = await client.send(http.Request('GET', _url));
    final failure = Completer<(Object, StackTrace)>();
    response.stream.listen(
      (_) {},
      onError: (Object error, StackTrace stack) =>
          failure.complete((error, stack)),
    );
    client.close();
    final (error, stack) = await failure.future;
    expect(error, isA<StateError>());
    expect(
      stack.toString().split('\n').first,
      contains('PublicMediaClient.close'),
    );
    await source.close();
  });

  test('an abort reaches a request that has not answered yet', () async {
    final client = PublicMediaClient(
      addressLookup: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return <InternetAddress>[_public];
      },
      transportFactory: (_, _, _) => _Transport(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      ),
    );
    final pending = client.send(http.Request('GET', _url));
    client.close();
    await expectLater(pending, throwsStateError);
  });

  test(
    'background preflight rejects unsafe initial DNS without fetching media',
    () async {
      await expectLater(
        validatePublicMediaDestination(
          _url,
          addressLookup: (_) async => <InternetAddress>[
            InternetAddress('192.168.2.1'),
          ],
        ),
        throwsA(isA<ProviderException>()),
      );
      await validatePublicMediaDestination(
        _url,
        addressLookup: (_) async => <InternetAddress>[_public],
      );
    },
  );
}

class _Transport extends http.BaseClient {
  _Transport(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
  @override
  void close() => closed = true;
}
