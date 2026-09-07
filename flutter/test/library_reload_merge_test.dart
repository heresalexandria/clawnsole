import 'dart:async';
import 'dart:convert';

import 'package:clawnsole/core/app_version.dart';
import 'package:clawnsole/core/google_drive_auth_base.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:clawnsole/app/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Every asynchronous library read the studio makes is a read of a library
/// that other code paths keep writing. Three reload paths used to answer by
/// replacing `snapshot.generations` with whatever the store happened to hold
/// when the read started — a preference write, the foreground reconcile, and
/// the provider-catalog refresh — so a record that appeared in memory while
/// the read was open simply vanished, and a stale copy of a record could
/// overwrite the newer one the studio was already showing.
///
/// These tests hold each read open, change the in-memory library underneath
/// it, and pin what the reload is allowed to do to that change.
void main() {
  group('library reloads', () {
    test(
      'a preference write keeps a record inserted while it was open',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);

        final write = fixture.controller.setThemeMode(AppThemeMode.dark);
        await fixture.untilRequested('setPreferences');
        fixture.insertInMemory(_film('delivered-while-open'));

        fixture.release();
        await write;

        expect(
          fixture.controller.generations.map((item) => item.localId),
          contains('delivered-while-open'),
          reason: 'the preference response predates the record',
        );
        expect(fixture.controller.themeMode, AppThemeMode.dark);
      },
    );

    test(
      'the foreground reconcile keeps a record inserted while it was open',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);

        final reconcile = fixture.controller.reconcileGenerationWork();
        await fixture.untilRequested('/state');
        fixture.insertInMemory(_film('delivered-while-open'));

        fixture.release();
        await reconcile;

        expect(
          fixture.controller.generations.map((item) => item.localId),
          contains('delivered-while-open'),
        );
      },
    );

    test(
      'a provider-catalog refresh keeps a record inserted while it was open',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);

        final refresh = fixture.controller.refreshProviderCatalog();
        await fixture.untilRequested('/state');
        fixture.insertInMemory(_film('delivered-while-open'));

        fixture.release();
        await refresh;

        expect(
          fixture.controller.generations.map((item) => item.localId),
          contains('delivered-while-open'),
        );
      },
    );

    for (final reload in <String, Future<void> Function(_Fixture fixture)>{
      'a preference write': (fixture) =>
          fixture.controller.setThemeMode(AppThemeMode.dark),
      'the foreground reconcile': (fixture) =>
          fixture.controller.reconcileGenerationWork(),
      'a provider-catalog refresh': (fixture) =>
          fixture.controller.refreshProviderCatalog(),
    }.entries) {
      test('${reload.key} never reverts a newer in-memory film', () async {
        // The store still holds the copy from before this device published
        // the film to Drive; memory holds the published swap.
        final fixture = _Fixture(
          stored: <Generation>[
            _film('a', status: 'Ready', resultUrl: 'https://provider/a.mp4'),
          ],
        );
        addTearDown(fixture.dispose);
        fixture.controller.snapshot = _snapshot(fixture.stored);

        final operation = reload.value(fixture);
        await fixture.untilRequested(
          reload.key == 'a preference write' ? 'setPreferences' : '/state',
        );
        fixture.insertInMemory(
          _film(
            'a',
            status: 'Ready',
            resultUrl: 'https://provider/a.mp4',
            resultAsset: const AssetReference(
              kind: 'drive',
              value: 'drive-file-a',
              label: 'a.mp4',
              contentType: 'video/mp4',
            ),
          ),
        );

        fixture.release();
        await operation;

        final card = fixture.controller.generations.singleWhere(
          (item) => item.localId == 'a',
        );
        expect(
          card.resultAsset?.kind,
          'drive',
          reason: 'a superseded read must not undo the published swap',
        );
      });
    }

    test('an unsuperseded read still adopts the store wholesale', () async {
      final fixture = _Fixture(
        stored: <Generation>[_film('from-another-device')],
      );
      addTearDown(fixture.dispose);

      fixture.release();
      await fixture.controller.reconcileGenerationWork();

      expect(
        fixture.controller.generations.map((item) => item.localId),
        <String>['from-another-device'],
      );
    });
  });
}

Generation _film(
  String id, {
  String status = 'Pending',
  String? resultUrl,
  AssetReference? resultAsset,
}) => Generation(
  localId: id,
  status: status,
  prompt: 'a long quiet take',
  mode: VideoMode.t2v,
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 5,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  ),
  createdAt: DateTime.utc(2026, 9, 6),
  updatedAt: DateTime.utc(2026, 9, 6),
  resultUrl: resultUrl,
  resultAsset: resultAsset,
  storage: LibraryStorage.drive,
);

LocalSnapshot _snapshot(List<Generation> generations) => LocalSnapshot(
  generations: generations,
  preferences: const AppPreferences(),
  hasApiKey: false,
  connectedProviders: const <String>{'runway'},
  storage: StorageStats(path: 'memory', bytes: 0, records: generations.length),
);

/// A real [AppController] over a real [WebGateway] whose library reads block
/// until the test releases them.
class _Fixture {
  _Fixture({List<Generation>? stored})
    : stored = stored ?? const <Generation>[] {
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      driveAuthorizer: _FixtureAuthorizer(),
      client: MockClient(_handle),
    );
    controller =
        AppController(
            gateway: gateway,
            providerCatalogClient: _FixedCatalogClient(),
          )
          ..snapshot = _snapshot(this.stored)
          ..loading = false
          ..selectedProviderId = 'runway'
          ..selectedModelId = 'seedance2_5';
  }

  final List<Generation> stored;
  late final AppController controller;
  final Completer<void> _gate = Completer<void>();
  final Set<String> _requested = <String>{};

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  void dispose() {
    release();
    controller.dispose();
  }

  /// Replaces the studio's library the way any other in-memory write does:
  /// through the snapshot setter, which bumps the revision the reads in
  /// flight were started at.
  void insertInMemory(Generation record) {
    final current = controller.snapshot!;
    controller.snapshot = current.copyWith(
      generations: <Generation>[
        record,
        ...current.generations.where((item) => item.localId != record.localId),
      ],
    );
  }

  Future<void> untilRequested(String marker) async {
    for (var attempt = 0; attempt < 2000; attempt += 1) {
      if (_requested.contains(marker)) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('The reload never asked for $marker.');
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    switch (path) {
      case '/account':
        return http.Response(jsonEncode({'provider': 'runway'}), 200);
      case '/composer-tabs':
        return http.Response('{}', 200);
      case '/provider-catalog-cache':
        return http.Response('null', 200);
      case '/state':
      case '/drive/refresh':
        // Every mutating gateway call is a PATCH of /state naming its action;
        // a plain GET is the library read.
        _requested.add(
          request.method == 'PATCH'
              ? (jsonDecode(request.body) as Map<String, dynamic>)['action']
                        as String? ??
                    ''
              : path,
        );
        await _gate.future;
        return http.Response(jsonEncode(_snapshot(stored).toJson()), 200);
      default:
        throw StateError('Unexpected request: ${request.url}');
    }
  }
}

/// Answers the catalog fetch immediately with the compiled-in providers, so
/// the refresh under test is only its snapshot reload.
class _FixedCatalogClient extends ProviderCatalogClient {
  _FixedCatalogClient()
    : super(
        client: MockClient(
          (_) async => throw StateError('The catalog fetch is stubbed.'),
        ),
      );

  @override
  Future<ProviderCatalogBundle> fetch({
    String appVersion = clawnsoleVersion,
    bool mobileTestBuild = clawnsoleMobileTestBuild,
  }) async => ProviderCatalogBundle(
    providers: videoProviders,
    cache: const <String, Object?>{'schema_version': 1},
    isMobileTest: false,
  );
}

class _FixtureAuthorizer implements GoogleDriveAuthorizer {
  @override
  bool get isAvailable => true;

  @override
  String get unavailableMessage => '';

  @override
  Future<String> authorize() async => 'token';

  @override
  Future<String?> authorizeSilently() async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
