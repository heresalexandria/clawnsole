import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_auth_base.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:clawnsole/core/temporary_media_source_io.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';
import 'support/memory_asset_streaming.dart';

void main() {
  for (final surface in ['direct', 'native', 'companion']) {
    test(
      '$surface exposes hosting readiness and account-bound consent',
      () async {
        final fixture = await _Fixture.create(surface);
        addTearDown(fixture.dispose);
        final first = await fixture.hosting.temporaryMediaHostStatus();
        expect(first.backendId, 'iCloudDrive');
        expect(first.readiness, TemporaryMediaReadiness.ready);
        expect(first.available, isTrue);
        expect(first.sharingAccepted, isFalse);
        expect(first.accountScope, 'opaque-apple-one');
        expect(
          first.cleanupSemantics,
          TemporaryMediaCleanupSemantics.deferredExpiry,
        );

        fixture.backend.account = 'opaque-apple-two';
        await expectLater(
          fixture.consent.acceptTemporaryMediaSharing(
            expectedBackendId: first.backendId,
            expectedAccountScope: first.accountScope!,
          ),
          throwsA(anything),
        );
        expect(fixture.backend.acceptedAccounts, isEmpty);
        final changed = await fixture.hosting.temporaryMediaHostStatus();
        await fixture.consent.acceptTemporaryMediaSharing(
          expectedBackendId: changed.backendId,
          expectedAccountScope: changed.accountScope!,
        );
        expect(
          (await fixture.hosting.temporaryMediaHostStatus()).sharingAccepted,
          isTrue,
        );
        expect(fixture.backend.acceptedAccounts, {'opaque-apple-two'});

        fixture.backend.readiness = TemporaryMediaReadiness.driveDisabled;
        final disabled = await fixture.hosting.temporaryMediaHostStatus();
        expect(disabled.available, isFalse);
        expect(disabled.readiness, TemporaryMediaReadiness.driveDisabled);
        expect(disabled.message, 'Enable iCloud Drive in Settings.');
      },
    );

    test(
      '$surface reports surviving publication separately from source cleanup',
      () async {
        final fixture = await _Fixture.create(surface);
        addTearDown(fixture.dispose);
        await fixture.accept();
        await fixture.seedPendingReference();
        final active = await fixture.hosting.temporaryMediaHostStatus();
        expect(active.activeLeases, 1);
        expect(active.publishedSnapshots, 1);
        expect(active.latestPublishedExpiry, fixture.backend.expiry);
        await fixture.host.release('pending-generation');
        final cleaned = await fixture.hosting.temporaryMediaHostStatus();
        expect(cleaned.activeLeases, 0);
        expect(cleaned.pendingCleanup, 0);
        expect(cleaned.publishedSnapshots, 1);
        expect(cleaned.latestPublishedExpiry, fixture.backend.expiry);
        expect(fixture.backend.released, 1);
        expect(
          fixture.journal.leases.single.state,
          TemporaryMediaLeaseState.sourceRemoved,
        );
        expect(
          jsonEncode(cleaned.toJson()),
          isNot(contains('bearer-capability')),
        );
      },
    );
  }

  for (final surface in ['direct', 'native', 'companion']) {
    test(
      '$surface rejects renderer-supplied file paths before hosting or provider traffic',
      () async {
        final fixture = await _Fixture.create(surface, stageSources: true);
        addTearDown(fixture.dispose);
        final outside = await Directory.systemTemp.createTemp(
          'unowned-renderer-media.',
        );
        addTearDown(() => outside.delete(recursive: true));
        final file = File('${outside.path}/private.mp4');
        await file.writeAsBytes([1, 2, 3]);
        await (fixture.gateway as ProviderGateway).setProviderApiKey(
          'apipod',
          'fixture-key',
        );
        await fixture.accept();
        for (final source in [file.path, file.uri.toString()]) {
          final now = DateTime.now().toUtc();
          await expectLater(
            fixture.gateway.submit(
              GenerationSubmission(
                record: Generation(
                  localId: 'unowned-${fixture.backend.stageAttempts}',
                  provider: 'apipod',
                  model: 'seedance-2.5-r2v',
                  status: 'Submitting',
                  prompt: 'Use the declared reference.',
                  mode: VideoMode.i2v,
                  config: const GenerationConfig(
                    aspectRatio: '16:9',
                    duration: 4,
                    resolution: '480p',
                    generateAudio: false,
                    safetyTolerance: 2,
                    draft: false,
                    references: [
                      MediaReferenceLabel(
                        label: 'clip.mp4',
                        kind: MediaReferenceKind.video,
                        durationSeconds: 4,
                      ),
                    ],
                  ),
                  createdAt: now,
                  updatedAt: now,
                ),
                input: {
                  'mode': 'i2v',
                  'prompt': 'Use the declared reference.',
                  'duration': 4,
                  'resolution': '480p',
                  'reference_videos': [source],
                },
                autoFixReferenceVideos: false,
              ),
            ),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains('Import it into Clawnsole'),
              ),
            ),
          );
          expect(await file.readAsBytes(), [1, 2, 3]);
          expect(fixture.backend.copies, isEmpty);
          expect(fixture.providerRequests, 0);
        }
        expect(fixture.backend.stageAttempts, 2);
      },
    );
  }

  for (final surface in ['native', 'companion']) {
    for (final cleanedLease in [false, true]) {
      test(
        '$surface retries a persisted Drive generation after restart with ${cleanedLease ? 'cleaned lease and changed saved references' : 'no old hosting lease'}',
        () async {
          final fixture = await _Fixture.create(surface, publishToDrive: true);
          addTearDown(fixture.dispose);
          fixture.acceptProviderSubmission = true;
          await (fixture.gateway as ProviderGateway).setProviderApiKey(
            'apipod',
            'fixture-key',
          );
          final oldTime = DateTime.utc(2026, 11, 8);
          if (cleanedLease) {
            // The new host has not loaded its journal yet. These are the
            // cleanup receipts left by the previous app process.
            fixture.journal.leases = [
              TemporaryMediaLease(
                id: 'old-cleaned-copy',
                operationId: 'previous-failed-generation',
                scopeId: fixture.backend.account!,
                backendId: 'iCloudDrive',
                cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
                provider: 'apipod',
                model: 'seedance-2.5-r2v',
                state: TemporaryMediaLeaseState.sourceRemoved,
                createdAt: oldTime,
                updatedAt: oldTime,
                publicationAttemptedAt: oldTime,
                publishedExpiresAt: fixture.backend.expiry,
                sourceRemovedAt: oldTime,
              ),
            ];
          }
          final retained = <AssetReference>[
            for (var index = 0; index < 2; index++)
              await fixture.drive!.writeAsset(
                Uint8List.fromList([1 + index, 2 + index, 3 + index]),
                label: 'motion-$index.mp4',
                contentType: 'video/mp4',
              ),
          ];
          final changedSavedReferences = <SavedReference>[
            if (cleanedLease)
              for (var index = 0; index < 2; index++)
                SavedReference(
                  id: 'saved-motion-$index',
                  name: 'Updated library motion $index',
                  kind: MediaReferenceKind.video,
                  asset: await fixture.drive!.writeAsset(
                    Uint8List.fromList([9, 8, 7, 6, 5 + index]),
                    label: 'library-source-$index.mov',
                    contentType: 'video/quicktime',
                  ),
                  durationSeconds: 8,
                  storage: LibraryStorage.drive,
                  createdAt: oldTime,
                  updatedAt: oldTime.add(const Duration(hours: 1)),
                ),
          ];
          final failed = Generation(
            localId: 'previous-failed-generation',
            provider: 'apipod',
            model: 'seedance-2.5-r2v',
            status: 'Error',
            error: 'The saved video file is missing.',
            prompt: 'Keep the original camera movement and the second subject.',
            mode: VideoMode.i2v,
            config: GenerationConfig(
              aspectRatio: '9:16',
              duration: 6,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              references: [
                for (final entry in retained.indexed)
                  MediaReferenceLabel(
                    label: entry.$2.label,
                    kind: MediaReferenceKind.video,
                    promptName: 'Video ${entry.$1 + 1}',
                    referenceId: 'saved-motion-${entry.$1}',
                    source: entry.$2,
                    durationSeconds: 2,
                  ),
              ],
            ),
            folderId: 'original-drive-folder',
            storage: LibraryStorage.drive,
            createdAt: oldTime,
            updatedAt: oldTime,
          );
          final diskRecord = StoredData.fromJson(
            jsonDecode(StoredData(generations: [failed]).encode())
                as Map<String, Object?>,
          ).generations.single;
          await fixture.hybrid.write(
            (await fixture.hybrid.read()).copyWith(
              generations: [diskRecord],
              savedReferences: changedSavedReferences,
              folders: [
                LibraryFolder(
                  id: 'original-drive-folder',
                  name: 'Original scene',
                  storage: LibraryStorage.drive,
                  createdAt: oldTime,
                ),
              ],
            ),
          );
          await fixture.accept();
          final hostedBytes = <List<int>>[];
          fixture.backend.stage = (source) async {
            expect(source.retained!.kind, 'drive');
            final staged = await stageTemporaryMediaSource(
              source,
              fixture.hybrid,
            );
            try {
              final expected = retained[hostedBytes.length];
              expect(source.retained!.value, expected.value);
              expect(staged.length, expected.bytes);
              expect(staged.sha256, expected.sha256);
              hostedBytes.add(await File(staged.path).readAsBytes());
            } finally {
              await staged.dispose();
            }
          };
          final controller = AppController(gateway: fixture.gateway)
            ..snapshot = await fixture.gateway.load()
            ..loading = false
            ..autoFixReferenceVideos = false;
          addTearDown(controller.dispose);
          controller.updateForm((form) {
            form.prompt = 'Unrelated work still being edited.';
            form.durationSeconds = 12;
            form.resolution = 'sd';
          });
          final activeTab = controller.activeComposerTab;
          final activeProvider = controller.selectedProviderId;
          final activeModel = controller.selectedModelId;
          final activeResolution = controller.form.resolution;
          final tabCount = controller.composerTabs.length;
          var confirmations = 0;
          await controller.retryGeneration(
            controller.generations.single,
            confirm: (confirmation) async {
              confirmations++;
              expect(confirmation.provider.id, 'apipod');
              return true;
            },
          );
          expect(confirmations, 0, reason: 'Sharing was already accepted.');
          expect(
            fixture.providerSubmissions,
            hasLength(1),
            reason: controller.notice,
          );
          expect(fixture.providerSubmissions.single['prompt'], failed.prompt);
          expect(fixture.providerSubmissions.single['model'], failed.model);
          expect(fixture.providerSubmissions.single['duration'], 6);
          expect(fixture.providerSubmissions.single['aspect_ratio'], '9:16');
          expect(hostedBytes, [
            [1, 2, 3],
            [2, 3, 4],
          ]);
          expect(fixture.backend.stageAttempts, 2);
          expect(fixture.backend.copies, hasLength(2));
          expect(controller.activeComposerTab, same(activeTab));
          expect(controller.composerTabs, hasLength(tabCount));
          expect(controller.form.prompt, 'Unrelated work still being edited.');
          expect(controller.form.durationSeconds, 12);
          expect(controller.form.resolution, activeResolution);
          expect(controller.selectedProviderId, activeProvider);
          expect(controller.selectedModelId, activeModel);
          final persisted = await fixture.local.read();
          final original = persisted.generations.singleWhere(
            (item) => item.localId == failed.localId,
          );
          expect(original.status, 'Error');
          expect(original.requestId, isNull);
          final retried = persisted.generations.singleWhere(
            (item) => item.localId != failed.localId,
          );
          expect(retried.status, 'Pending');
          expect(retried.requestId, 'accepted-task');
          expect(retried.prompt, failed.prompt);
          expect(retried.config.aspectRatio, '9:16');
          expect(retried.config.duration, 6);
          expect(retried.config.resolution, 'hd');
          expect(retried.config.generateAudio, isTrue);
          expect(retried.folderId, 'original-drive-folder');
          expect(retried.storage, LibraryStorage.drive);
          expect(
            retried.config.references!.map((item) => item.source!.value),
            retained.map((item) => item.value),
          );
          expect(
            retried.config.references!.map((item) => item.durationSeconds),
            [2, 2],
          );
          expect(retried.config.references!.map((item) => item.promptName), [
            'Video 1',
            'Video 2',
          ]);
          expect(
            fixture.journal.leases
                .where((lease) => lease.operationId == retried.localId)
                .map((lease) => lease.state),
            [
              TemporaryMediaLeaseState.accepted,
              TemporaryMediaLeaseState.accepted,
            ],
          );
        },
      );
    }

    test(
      '$surface hosts imported references after Drive moves their staged files',
      () async {
        final fixture = await _Fixture.create(surface, publishToDrive: true);
        addTearDown(fixture.dispose);
        fixture.acceptProviderSubmission = true;
        await (fixture.gateway as ProviderGateway).setProviderApiKey(
          'apipod',
          'fixture-key',
        );
        await fixture.accept();
        final stagedBytes = <List<int>>[];
        fixture.backend.stage = (source) async {
          // The host has captured both local references. Run the real upload
          // pass before it opens either file, including the cache adoption
          // rename that invalidates that captured local path.
          if (stagedBytes.isEmpty) {
            expect(await fixture.flushDriveUploads(), isTrue);
            expect(fixture.drive!.adopted, hasLength(2));
          }
          expect(source.retained?.kind, 'local');
          expect(
            await File.fromUri(
              await fixture.local.assetUri(source.retained!),
            ).exists(),
            isFalse,
          );
          final staged = await stageTemporaryMediaSource(
            source,
            fixture.hybrid,
          );
          try {
            stagedBytes.add(await File(staged.path).readAsBytes());
          } finally {
            await staged.dispose();
          }
        };
        final now = DateTime.now().toUtc();
        final accepted = await fixture.gateway.submit(
          GenerationSubmission(
            record: Generation(
              localId: 'drive-hosting-race',
              provider: 'apipod',
              model: 'seedance-2.5-r2v',
              status: 'Submitting',
              prompt: 'Use both motion references.',
              mode: VideoMode.i2v,
              config: const GenerationConfig(
                aspectRatio: '16:9',
                duration: 4,
                resolution: 'hd',
                generateAudio: false,
                safetyTolerance: 2,
                draft: false,
                references: [
                  MediaReferenceLabel(
                    label: 'first.mp4',
                    kind: MediaReferenceKind.video,
                    durationSeconds: 2,
                  ),
                  MediaReferenceLabel(
                    label: 'second.mp4',
                    kind: MediaReferenceKind.video,
                    durationSeconds: 2,
                  ),
                ],
              ),
              createdAt: now,
              updatedAt: now,
              storage: LibraryStorage.drive,
            ),
            input: {
              'mode': 'i2v',
              'prompt': 'Use both motion references.',
              'duration': 4,
              'resolution': 'hd',
              'reference_videos': [
                'data:video/mp4;base64,AQID',
                'data:video/mp4;base64,BAUG',
              ],
            },
            autoFixReferenceVideos: false,
          ),
        );
        expect(stagedBytes, [
          [1, 2, 3],
          [4, 5, 6],
        ]);
        expect(fixture.providerSubmissions, hasLength(1));
        expect(fixture.providerSubmissions.single['video_urls'], hasLength(2));
        expect(accepted.requestId, 'accepted-task');
        expect(accepted.status, 'Pending');
        final saved = (await fixture.local.read()).generations.single;
        expect(saved.requestId, 'accepted-task');
        expect(
          saved.config.references!.map((reference) => reference.source!.kind),
          everyElement('drive'),
        );
        expect(fixture.drive!.assets, hasLength(2));
      },
    );

    test(
      '$surface Google Drive disconnect preserves independent iCloud references',
      () async {
        final fixture = await _Fixture.create(surface);
        addTearDown(fixture.dispose);
        await fixture.accept();
        await fixture.seedPendingReference();
        await (fixture.gateway as GoogleDriveGateway).disconnectGoogleDrive();
        expect(fixture.authorizer.disconnects, 1);
        expect(fixture.backend.released, 0);
        expect(fixture.backend.copies, hasLength(1));
        final status = await fixture.hosting.temporaryMediaHostStatus();
        expect(status.available, isTrue);
        expect(status.sharingAccepted, isTrue);
        expect(status.activeLeases, 1);
        expect(
          fixture.journal.leases.single.state,
          TemporaryMediaLeaseState.accepted,
        );
      },
    );
  }

  test(
    'companion protects sharing status and consent with its launch session',
    () async {
      final fixture = await _Fixture.create('companion');
      addTearDown(fixture.dispose);
      final base = fixture.base!;
      final unauthenticatedStatus = await http.get(
        base.resolve('/temporary-media/status'),
      );
      expect(unauthenticatedStatus.statusCode, 403);
      final unauthenticatedConsent = await http.post(
        base.resolve('/temporary-media/accept-sharing'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'expectedBackendId': 'iCloudDrive',
          'expectedAccountScope': fixture.backend.account,
        }),
      );
      expect(unauthenticatedConsent.statusCode, 403);
      expect(fixture.backend.acceptedAccounts, isEmpty);
      final unbound = await fixture.renderer!.post(
        base.resolve('/temporary-media/accept-sharing'),
        headers: {'content-type': 'application/json'},
        body: '{}',
      );
      expect(unbound.statusCode, isNot(200));
      expect(fixture.backend.acceptedAccounts, isEmpty);
      await fixture.accept();
      expect(fixture.backend.acceptedAccounts, {'opaque-apple-one'});
    },
  );
}

class _Fixture {
  _Fixture(this.directory);

  static Future<_Fixture> create(
    String surface, {
    bool stageSources = false,
    bool publishToDrive = false,
  }) async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('hosting-gateway.'),
    );
    fixture.local = LocalDataStore(documentsDirectory: fixture.directory);
    if (stageSources) {
      fixture.backend.stage = (source) async {
        final staged = await stageTemporaryMediaSource(source, fixture.local);
        await staged.dispose();
      };
    }
    final providerRouter = ProviderApiRouter(
      apipod: ApipodApi(client: fixture.noNetwork),
    );
    if (publishToDrive) {
      fixture.drive = _PublishingDriveStore(fixture.directory);
    }
    final hybrid = fixture.hybrid = HybridDataStore(
      local: fixture.local,
      drive: fixture.drive,
    );
    if (publishToDrive) await hybrid.connect('fixture-token', 'Clawnsole');
    final vault = SettingsVaultDataStore(
      delegate: hybrid,
      secureStore: MemorySecureValueStore(),
    );
    fixture.host = TemporaryMediaHost(
      journal: fixture.journal,
      backend: fixture.backend,
    );
    if (surface == 'companion') {
      fixture.companionStore = CompanionHybridStore(hybrid, vault: vault);
      fixture.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      fixture.base = Uri.parse('http://127.0.0.1:${fixture.server!.port}');
      final app = CompanionApp.hybrid(
        store: fixture.companionStore!,
        api: BflApi(client: fixture.noNetwork),
        providerRouter: providerRouter,
        temporaryMediaHost: fixture.host,
        requestToken: 'fixture-local-session',
        allowedOrigin: fixture.base!.origin,
      );
      fixture.subscription = fixture.server!.listen(app.handle);
      fixture.renderer = _SessionClient();
      fixture.gateway = WebGateway(
        client: fixture.renderer,
        baseUrl: fixture.base,
        driveAuthorizer: fixture.authorizer,
      );
    } else if (surface == 'native') {
      fixture.native = NativeGateway(
        hybridStore: hybrid,
        settingsVaultStore: vault,
        providerRouter: providerRouter,
        temporaryMediaHost: fixture.host,
        driveAuthorizer: fixture.authorizer,
        client: fixture.noNetwork,
        isIos: true,
      );
      fixture.gateway = fixture.native!;
    } else {
      fixture.gateway = DirectGateway(
        store: vault,
        providerRouter: providerRouter,
        temporaryMediaHost: fixture.host,
        client: fixture.noNetwork,
      );
    }
    return fixture;
  }

  final Directory directory;
  final backend = _PublicationBackend();
  final journal = _Journal();
  final authorizer = _Authorizer();
  int providerRequests = 0;
  bool acceptProviderSubmission = false;
  final providerSubmissions = <Map<String, Object?>>[];
  late final noNetwork = MockClient((request) async {
    providerRequests++;
    if (acceptProviderSubmission &&
        request.method == 'GET' &&
        request.url.path == '/v1/account/status') {
      return http.Response('{"code":200,"data":{}}', 200);
    }
    if (acceptProviderSubmission &&
        request.method == 'POST' &&
        request.url.path == '/v1/pricing/estimate') {
      return http.Response(
        '{"code":200,"data":{"price":1,"currency":"USD"}}',
        200,
      );
    }
    if (acceptProviderSubmission &&
        request.method == 'POST' &&
        request.url.path == '/v1/videos/generations') {
      providerSubmissions.add(
        (jsonDecode(request.body) as Map).cast<String, Object?>(),
      );
      return http.Response(
        jsonEncode({
          'code': 200,
          'data': {'task_id': 'accepted-task'},
        }),
        200,
      );
    }
    throw StateError('Unexpected external request: ${request.url.host}');
  });
  late LocalDataStore local;
  late HybridDataStore hybrid;
  _PublishingDriveStore? drive;
  late TemporaryMediaHost host;
  late AppGateway gateway;
  NativeGateway? native;
  CompanionHybridStore? companionStore;
  HttpServer? server;
  Uri? base;
  StreamSubscription<HttpRequest>? subscription;
  _SessionClient? renderer;

  TemporaryMediaHostingGateway get hosting =>
      gateway as TemporaryMediaHostingGateway;
  TemporaryMediaConsentGateway get consent =>
      gateway as TemporaryMediaConsentGateway;

  Future<bool> flushDriveUploads() =>
      companionStore?.flushDriveUploads() ?? native!.flushDriveUploads();

  Future<void> accept() async {
    final status = await hosting.temporaryMediaHostStatus();
    await consent.acceptTemporaryMediaSharing(
      expectedBackendId: status.backendId,
      expectedAccountScope: status.accountScope!,
    );
  }

  Future<void> seedPendingReference() async {
    final now = DateTime.now().toUtc();
    final record = Generation(
      localId: 'pending-generation',
      provider: 'apipod',
      model: 'seedance-2.5-r2v',
      status: 'Pending',
      requestId: 'fixture-task',
      pollingUrl: 'https://api.apipod.ai/v1/videos/status/fixture-task',
      prompt: 'A test reference',
      mode: VideoMode.i2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 5,
        resolution: 'hd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );
    await local.write(StoredData(generations: [record]));
    await host.prepare(record, {
      'reference_videos': ['data:video/mp4;base64,AQID'],
    });
    await host.beforeSend(record.localId);
    await host.accepted(record);
  }

  Future<void> dispose() async {
    native?.dispose();
    companionStore?.dispose();
    renderer?.close();
    await subscription?.cancel();
    await server?.close(force: true);
    noNetwork.close();
    await directory.delete(recursive: true);
  }
}

class _PublishingDriveStore extends GoogleDriveStore with MemoryAssetStreaming {
  _PublishingDriveStore(this.directory);

  final Directory directory;
  StoredData data = const StoredData();
  final assets = <String, Uint8List>{};
  final adopted = <String>[];
  GoogleDriveConnection _connection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  @override
  GoogleDriveConnection get connection => _connection;

  @override
  Future<StoredData> connect(String accessToken, String folderName) async {
    _connection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connected,
      folderName: folderName,
      folderId: 'fixture-drive-root',
    );
    return data;
  }

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async =>
      data = googleDrivePortableData(value);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    final id = 'published-${assets.length}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'drive',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value]!;

  @override
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async {
    final bytes = await readAsset(reference);
    return GoogleDriveByteStream(
      Stream<List<int>>.value(bytes),
      contentLength: bytes.length,
    );
  }

  @override
  Future<Uri?> adoptPublishedAsset(
    AssetReference reference,
    Uri localFile,
  ) async {
    final target = File('${directory.path}/cached-${reference.value}.mp4');
    await File.fromUri(localFile).rename(target.path);
    adopted.add(reference.value);
    return target.uri;
  }

  @override
  Future<StoredData> repairMissingCachedAssets(StoredData value) async => value;

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'fixture-drive', bytes: 0, records: records);
}

class _PublicationBackend
    implements
        TemporaryMediaBackend,
        TemporaryMediaBackendCapabilities,
        TemporaryMediaConsentBackend {
  String? account = 'opaque-apple-one';
  @override
  String? scopeId;
  @override
  String get backendId => 'iCloudDrive';
  TemporaryMediaReadiness readiness = TemporaryMediaReadiness.ready;
  final acceptedAccounts = <String>{};
  final copies = <String, TemporaryMediaCopy>{};
  final expiry = DateTime.now().toUtc().add(const Duration(days: 30));
  int released = 0;
  int stageAttempts = 0;
  Future<void> Function(TemporaryMediaSource)? stage;

  @override
  Future<TemporaryMediaBackendAvailability> refreshAvailability() async {
    scopeId = account;
    return TemporaryMediaBackendAvailability(
      backendId: backendId,
      readiness: readiness,
      accountScope: account,
      message: readiness == TemporaryMediaReadiness.driveDisabled
          ? 'Enable iCloud Drive in Settings.'
          : null,
      cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
    );
  }

  @override
  Future<bool> isSharingAccepted() async => acceptedAccounts.contains(account);
  @override
  Future<void> acceptSharing() async => acceptedAccounts.add(account!);
  @override
  Future<List<TemporaryMediaCopy>> findCopies(
    TemporaryMediaLease lease,
  ) async => [if (copies[lease.id] != null) copies[lease.id]!];
  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async {
    stageAttempts++;
    await stage?.call(source);
    return copies[lease.id] = TemporaryMediaCopy(
      fileId: lease.id,
      publishedAt: DateTime.now().toUtc(),
      expiresAt: expiry,
    );
  }

  @override
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async => TemporaryMediaShare(
    url: 'https://cvws.icloud-content.com/fixture?token=bearer-capability',
    expiresAt: expiry,
    cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
  );
  @override
  Future<void> releaseCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    expect(lease.scopeId, account);
    if (copies.remove(lease.id) != null) released++;
  }
}

class _Journal implements TemporaryMediaLeaseJournal {
  List<TemporaryMediaLease> leases = [];
  @override
  Future<List<TemporaryMediaLease>> read() async => List.of(leases);
  @override
  Future<void> write(List<TemporaryMediaLease> value) async =>
      leases = List.of(value);
}

class _Authorizer implements GoogleDriveAuthorizer {
  int disconnects = 0;
  @override
  bool get isAvailable => true;
  @override
  String get unavailableMessage => '';
  @override
  Future<String> authorize() async =>
      throw StateError('Unexpected Google login');
  @override
  Future<String?> authorizeSilently() async => null;
  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

class _SessionClient extends http.BaseClient {
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['X-Clawnsole-Session'] = 'fixture-local-session';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
