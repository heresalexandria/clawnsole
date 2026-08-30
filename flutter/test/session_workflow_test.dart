import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/session_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy work remains visible before the first session exists', () {
    final now = DateTime.utc(2026, 8, 30, 12);
    final legacy = Generation(
      localId: 'legacy-generation',
      status: 'Ready',
      prompt: 'Legacy prompt',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );
    final gateway = _SessionWorkflowGateway(
      _emptySnapshot().copyWith(generations: <Generation>[legacy]),
    );
    final controller = AppController(gateway: gateway)
      ..snapshot = gateway.snapshot;
    addTearDown(controller.dispose);

    expect(controller.activeGenerationSession, isNull);
    expect(controller.recentGenerations, <Generation>[legacy]);
  });

  test('submissions reuse sessions until the user starts a new one', () async {
    final gateway = _SessionWorkflowGateway(_emptySnapshot());
    final naming = _RecordingSessionNameGenerator();
    final controller = AppController(
      gateway: gateway,
      sessionNameGenerator: naming,
    )..snapshot = gateway.snapshot;
    addTearDown(controller.dispose);

    controller.form.prompt = 'A clockwork garden waking at sunrise';
    await controller.submit();

    expect(controller.generationSessions, hasLength(1));
    final firstSession = controller.generationSessions.single;
    final firstGeneration = controller.generations.single;
    expect(firstSession.role, LibraryFolderRole.session);
    expect(firstSession.automaticName, isTrue);
    expect(firstGeneration.folderId, firstSession.id);
    expect(firstGeneration.sessionId, firstSession.id);
    expect(naming.sources, <String>['A clockwork garden waking at sunrise']);

    controller.form.prompt = 'A close-up of the garden gate';
    await controller.submit();

    expect(controller.generationSessions, hasLength(1));
    expect(controller.generations, hasLength(2));
    expect(
      controller.generations.map((item) => item.sessionId).toSet(),
      <String?>{firstSession.id},
    );
    expect(
      naming.sources,
      <String>['A clockwork garden waking at sunrise'],
      reason: 'only the first generation may name an existing session',
    );

    await controller.startNewGenerationSession();
    expect(controller.activeGenerationSession, isNull);
    expect(controller.recentGenerations, isEmpty);
    controller.form.prompt = 'A paper city unfolding beside the sea';
    await controller.submit();

    expect(controller.generationSessions, hasLength(2));
    final newest = controller.generations.first;
    expect(newest.sessionId, isNot(firstSession.id));
    expect(newest.folderId, newest.sessionId);
    expect(controller.activeGenerationSessionId, newest.sessionId);
    expect(naming.sources, <String>[
      'A clockwork garden waking at sunrise',
      'A paper city unfolding beside the sea',
    ]);

    expect(await controller.saveLibraryFolder('Archive'), isTrue);
    final archive = controller.folders.singleWhere(
      (folder) => folder.name == 'Archive',
    );
    expect(archive.isSession, isFalse);
    expect(
      await controller.organizeGeneration(
        firstGeneration.localId,
        folderId: archive.id,
        tags: const <String>['Campaign'],
      ),
      isTrue,
    );
    final moved = controller.generations.singleWhere(
      (item) => item.localId == firstGeneration.localId,
    );
    expect(moved.folderId, archive.id);
    expect(moved.sessionId, firstSession.id);
    expect(moved.tags, const <String>['Campaign']);
  });

  test('manual session rename prevents a delayed automatic rename', () async {
    final naming = _DelayedSessionNameGenerator();
    addTearDown(naming.completeIfPending);
    final gateway = _SessionWorkflowGateway(_emptySnapshot());
    final controller = AppController(
      gateway: gateway,
      sessionNameGenerator: naming,
    )..snapshot = gateway.snapshot;
    addTearDown(controller.dispose);

    controller.form.prompt = 'A lunar greenhouse full of silver orchids';
    await controller.submit();
    final automatic = controller.generationSessions.single;
    expect(automatic.automaticName, isTrue);
    expect(naming.sources, <String>[
      'A lunar greenhouse full of silver orchids',
    ]);

    expect(
      await controller.saveLibraryFolder(
        'My greenhouse film',
        existing: automatic,
        parentId: automatic.parentId,
      ),
      isTrue,
    );
    var renamed = controller.sessionById(automatic.id)!;
    expect(renamed.name, 'My greenhouse film');
    expect(renamed.automaticName, isFalse);

    naming.complete('Machine suggested title');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    renamed = controller.sessionById(automatic.id)!;
    expect(renamed.name, 'My greenhouse film');
    expect(renamed.automaticName, isFalse);
  });

  test('a rejected session move keeps the previous base destination', () async {
    final now = DateTime.utc(2026, 8, 30, 12);
    final first = LibraryFolder(
      id: 'folder-first',
      name: 'First destination',
      createdAt: now,
    );
    final second = LibraryFolder(
      id: 'folder-second',
      name: 'Second destination',
      createdAt: now,
    );
    final session = LibraryFolder(
      id: 'session-active',
      name: 'Active session',
      createdAt: now,
      parentId: first.id,
      role: LibraryFolderRole.session,
    );
    final gateway = _SessionWorkflowGateway(
      LocalSnapshot(
        generations: const <Generation>[],
        folders: <LibraryFolder>[first, second, session],
        preferences: const AppPreferences(
          lastLocalGenerationFolderId: 'folder-first',
          lastLocalGenerationSessionId: 'session-active',
        ),
        hasApiKey: true,
        connectedProviders: const <String>{'bfl'},
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    )..rejectSessionMoves = true;
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.setGenerationFolder(second.id);

    expect(controller.selectedGenerationFolderId, first.id);
    expect(controller.activeGenerationSession?.parentId, first.id);
    expect(gateway.snapshot.preferences.lastLocalGenerationFolderId, first.id);
  });
}

LocalSnapshot _emptySnapshot() => const LocalSnapshot(
  generations: <Generation>[],
  preferences: AppPreferences(),
  hasApiKey: true,
  connectedProviders: <String>{'bfl'},
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

class _RecordingSessionNameGenerator implements SessionNameGenerator {
  final List<String> sources = <String>[];

  @override
  Future<String?> generate(String source) async {
    sources.add(source);
    return null;
  }
}

class _DelayedSessionNameGenerator implements SessionNameGenerator {
  final Completer<String?> _result = Completer<String?>();
  final List<String> sources = <String>[];

  @override
  Future<String?> generate(String source) {
    sources.add(source);
    return _result.future;
  }

  void complete(String? value) {
    if (!_result.isCompleted) _result.complete(value);
  }

  void completeIfPending() => complete(null);
}

class _SessionWorkflowGateway
    implements AppGateway, LibraryOrganizationGateway {
  _SessionWorkflowGateway(this.snapshot);

  LocalSnapshot snapshot;
  bool rejectSessionMoves = false;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder) async {
    final folders = List<LibraryFolder>.from(snapshot.folders);
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (rejectSessionMoves &&
        folder.isSession &&
        index >= 0 &&
        folders[index].parentId != folder.parentId) {
      throw StateError('Rejected session move.');
    }
    if (index < 0) {
      folders.add(folder);
    } else {
      folders[index] = folder;
    }
    snapshot = snapshot.copyWith(folders: folders);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> deleteLibraryFolder(String folderId) async {
    snapshot = snapshot.copyWith(
      folders: snapshot.folders
          .where((folder) => folder.id != folderId)
          .toList(),
      generations: snapshot.generations
          .map(
            (item) => item.copyWith(
              clearFolder: item.folderId == folderId,
              clearSession: item.sessionId == folderId,
            ),
          )
          .toList(),
    );
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  }) async {
    snapshot = snapshot.copyWith(
      generations: snapshot.generations
          .map(
            (item) => item.localId == localId
                ? item.copyWith(
                    folderId: folderId,
                    clearFolder: folderId == null,
                    tags: tags,
                  )
                : item,
          )
          .toList(),
    );
    return snapshot;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    final accepted = submission.record.copyWith(
      status: 'Pending',
      requestId: 'request-${snapshot.generations.length + 1}',
      pollingUrl: 'https://example.test/generation',
    );
    snapshot = snapshot.copyWith(
      generations: <Generation>[accepted, ...snapshot.generations],
    );
    return accepted;
  }

  @override
  Future<double> getCredits() async => 1000;

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 1000;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async {
    snapshot = snapshot.copyWith(
      generations: snapshot.generations
          .where((item) => item.localId != localId)
          .toList(),
    );
    return snapshot;
  }

  @override
  Future<LocalSnapshot> clearHistory() async {
    snapshot = snapshot.copyWith(generations: const <Generation>[]);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> clearPreferences() async {
    snapshot = snapshot.copyWith(preferences: const AppPreferences());
    return snapshot;
  }

  @override
  Future<LocalSnapshot> clearApiKey() async => snapshot;

  @override
  Future<LocalSnapshot> clearAll() async {
    snapshot = _emptySnapshot();
    return snapshot;
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}
