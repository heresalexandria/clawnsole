import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../core/gateway.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';

class PickedAsset {
  const PickedAsset({
    required this.name,
    required this.bytes,
    required this.mimeType,
    this.retained,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final AssetReference? retained;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

class KeyframeDraft {
  const KeyframeDraft({
    required this.id,
    required this.label,
    required this.role,
    required this.source,
    required this.seconds,
    this.asset,
    this.retained,
  });

  final String id;
  final String label;
  final KeyframeRole role;
  final String source;
  final double seconds;
  final PickedAsset? asset;
  final AssetReference? retained;

  String get requestSource => asset?.dataUrl ?? source.trim();

  KeyframeDraft copyWith({String? label, String? source, double? seconds}) =>
      KeyframeDraft(
        id: id,
        label: label ?? this.label,
        role: role,
        source: source ?? this.source,
        seconds: seconds ?? this.seconds,
        asset: asset,
        retained: source == null ? retained : null,
      );
}

class GenerationFormState {
  VideoMode mode = VideoMode.t2v;
  String prompt = '';
  String aspectRatio = '16:9';
  bool autoDuration = true;
  int durationSeconds = 8;
  String resolution = 'hd';
  bool generateAudio = true;
  int safetyTolerance = 2;
  bool draft = false;
  bool exactTiming = false;
  List<KeyframeDraft> keyframes = <KeyframeDraft>[];
  PickedAsset? videoAsset;
  String videoUrl = '';
  PickedAsset? draftAsset;
  String draftUrl = '';

  Object get duration => autoDuration ? 'auto' : durationSeconds;

  bool get hasStartFrame =>
      keyframes.any((frame) => frame.role == KeyframeRole.start);
  bool get hasEndFrame =>
      keyframes.any((frame) => frame.role == KeyframeRole.end);

  bool get hasPlainKeyframeLayout {
    if (keyframes.length == 1) {
      return keyframes.single.role == KeyframeRole.start;
    }
    return keyframes.length >= 2 && hasStartFrame && hasEndFrame;
  }

  bool get requiresTimedKeyframes =>
      mode == VideoMode.i2v && keyframes.isNotEmpty && !hasPlainKeyframeLayout;
  bool get usesTimedKeyframes => exactTiming || requiresTimedKeyframes;
  bool get requiresFixedDuration =>
      mode == VideoMode.i2v && (usesTimedKeyframes || keyframes.length > 2);
}

class AppController extends ChangeNotifier {
  AppController({AppGateway? gateway}) : gateway = gateway ?? createGateway();

  final AppGateway gateway;
  final GenerationFormState form = GenerationFormState();

  LocalSnapshot? snapshot;
  AppSection section = AppSection.create;
  LibraryFilter libraryFilter = LibraryFilter.all;
  String librarySearch = '';
  double? credits;
  bool loading = true;
  bool submitting = false;
  bool refreshingCredits = false;
  String? loadError;
  String? creditError;
  String? notice;

  Timer? _pollTimer;
  Timer? _creditTimer;
  Timer? _noticeTimer;
  bool _polling = false;
  final Set<String> _retentionAttempts = <String>{};
  final Set<String> _statusChecks = <String>{};
  int _idCounter = 0;

  List<Generation> get generations => snapshot?.generations ?? const [];
  bool get hasApiKey => snapshot?.hasApiKey ?? false;
  bool get supportsPhotoLibrarySave => gateway.supportsPhotoLibrarySave;
  StorageStats get storage =>
      snapshot?.storage ?? const StorageStats(path: '', bytes: 0, records: 0);
  int get workingCount => generations.where((item) => item.isWorking).length;
  int get readyCount => generations.where((item) => item.isReady).length;
  double get spentCredits =>
      generations.fold(0, (total, item) => total + (item.cost ?? 0));
  bool isCheckingStatus(String localId) => _statusChecks.contains(localId);

  List<Generation> get filteredGenerations {
    final query = librarySearch.trim().toLowerCase();
    return generations.where((item) {
      if (query.isNotEmpty && !item.prompt.toLowerCase().contains(query)) {
        return false;
      }
      return switch (libraryFilter) {
        LibraryFilter.all => true,
        LibraryFilter.working => item.isWorking,
        LibraryFilter.ready => item.isReady,
        LibraryFilter.failed => item.isFailed,
      };
    }).toList();
  }

  AssetReference? _reference(PickedAsset? asset, String url, String label) {
    if (asset?.retained != null) return asset!.retained;
    final remote = Uri.tryParse(url.trim());
    return remote?.scheme == 'https'
        ? AssetReference(kind: 'remote', value: url.trim(), label: label)
        : null;
  }

  GenerationConfig get currentConfig {
    final orderedFrames = _orderedFrames();
    return GenerationConfig(
      aspectRatio: form.aspectRatio,
      duration: form.duration,
      resolution: form.resolution,
      generateAudio: form.generateAudio,
      safetyTolerance: form.safetyTolerance,
      draft: form.draft,
      exactTiming: form.usesTimedKeyframes,
      keyframes: form.mode == VideoMode.i2v
          ? orderedFrames
                .map(
                  (frame) => KeyframeLabel(
                    label: frame.label,
                    role: frame.role,
                    seconds: form.usesTimedKeyframes ? frame.seconds : null,
                    source:
                        frame.asset?.retained ??
                        frame.retained ??
                        _reference(null, frame.source, frame.label),
                  ),
                )
                .toList()
          : null,
      sourceLabel: switch (form.mode) {
        VideoMode.v2v =>
          form.videoAsset?.name ??
              (form.videoUrl.trim().isEmpty ? null : form.videoUrl.trim()),
        VideoMode.draftEnhance =>
          form.draftAsset?.name ??
              (form.draftUrl.trim().isEmpty ? null : form.draftUrl.trim()),
        _ => null,
      },
      source: switch (form.mode) {
        VideoMode.v2v => _reference(
          form.videoAsset,
          form.videoUrl,
          form.videoAsset?.name ?? 'Starting video',
        ),
        VideoMode.draftEnhance => _reference(
          form.draftAsset,
          form.draftUrl,
          form.draftAsset?.name ?? 'FLUX 3 draft cache',
        ),
        _ => null,
      },
    );
  }

  CreditEstimate get currentEstimate =>
      estimateCredits(form.mode, currentConfig, generations);

  Future<void> initialize() async {
    try {
      _apply(await gateway.load());
      if (generations.isNotEmpty) {
        await _restoreGenerationSettings(generations.first);
      }
      if (hasApiKey) {
        unawaited(refreshCredits());
        unawaited(pollWorking());
      }
    } on Object catch (error) {
      loadError = _message(error);
    } finally {
      loading = false;
      notifyListeners();
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(pollWorking()),
    );
    _creditTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (hasApiKey) unawaited(refreshCredits());
    });
  }

  void _apply(LocalSnapshot value) {
    snapshot = value;
    section = value.preferences.activeSection;
    libraryFilter = value.preferences.libraryFilter;
    loadError = null;
    notifyListeners();
  }

  void showNotice(String message) {
    notice = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('ProviderException: ', '')
      .replaceFirst('Exception: ', '');

  Future<void> navigate(AppSection value) async {
    section = value;
    notifyListeners();
    try {
      _apply(
        await gateway.setPreferences(
          AppPreferences(activeSection: value, libraryFilter: libraryFilter),
        ),
      );
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLibraryFilter(LibraryFilter value) async {
    libraryFilter = value;
    notifyListeners();
    try {
      _apply(
        await gateway.setPreferences(
          AppPreferences(activeSection: section, libraryFilter: value),
        ),
      );
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void setSearch(String value) {
    librarySearch = value;
    notifyListeners();
  }

  void updateForm(void Function(GenerationFormState value) update) {
    update(form);
    if (form.draft) form.resolution = 'hd';
    if (form.requiresFixedDuration) form.autoDuration = false;
    notifyListeners();
  }

  Future<PickedAsset?> _pick({
    required FileType type,
    List<String>? extensions,
  }) async {
    final result = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: extensions,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null) return null;
    final bytes = file.bytes;
    if (bytes == null) throw StateError('The selected file could not be read.');
    return PickedAsset(
      name: file.name,
      bytes: bytes,
      mimeType:
          lookupMimeType(file.name, headerBytes: bytes) ??
          'application/octet-stream',
    );
  }

  bool canAddFrame(KeyframeRole role) =>
      form.keyframes.length < bflProvider.maxKeyframes &&
      (role == KeyframeRole.middle ||
          !form.keyframes.any((frame) => frame.role == role));

  double _suggestedFrameTime(KeyframeRole role) => switch (role) {
    KeyframeRole.start => 0,
    KeyframeRole.end => form.durationSeconds.toDouble(),
    KeyframeRole.middle =>
      form.durationSeconds *
          (form.keyframes
                  .where((frame) => frame.role == KeyframeRole.middle)
                  .length +
              1) /
          (form.keyframes
                  .where((frame) => frame.role == KeyframeRole.middle)
                  .length +
              2),
  };

  void _appendFrame(
    KeyframeRole role, {
    required String label,
    PickedAsset? asset,
  }) {
    if (!canAddFrame(role)) return;
    form.keyframes = <KeyframeDraft>[
      ...form.keyframes,
      KeyframeDraft(
        id: _uid(),
        label: label,
        role: role,
        source: '',
        seconds: _suggestedFrameTime(role),
        asset: asset,
      ),
    ];
    if (form.requiresFixedDuration) form.autoDuration = false;
    notifyListeners();
  }

  Future<void> addImageFrame(KeyframeRole role) async {
    if (!canAddFrame(role)) return;
    try {
      final asset = await _pick(type: FileType.image);
      if (asset != null) _appendFrame(role, label: asset.name, asset: asset);
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void addUrlFrame(KeyframeRole role) =>
      _appendFrame(role, label: '${role.label} URL');

  void setExactTiming(bool value) {
    form.exactTiming = value;
    if (value) {
      form.autoDuration = false;
      form.keyframes = form.keyframes.map((frame) {
        if (frame.role == KeyframeRole.start) {
          return frame.copyWith(seconds: 0);
        }
        if (frame.role == KeyframeRole.end) {
          return frame.copyWith(seconds: form.durationSeconds.toDouble());
        }
        return frame;
      }).toList();
    }
    notifyListeners();
  }

  void setDurationSeconds(int value) {
    form.durationSeconds = value;
    form.keyframes = form.keyframes.map((frame) {
      return frame.role == KeyframeRole.end
          ? frame.copyWith(seconds: value.toDouble())
          : frame;
    }).toList();
    notifyListeners();
  }

  List<KeyframeDraft> _orderedFrames() {
    final frames = List<KeyframeDraft>.from(form.keyframes);
    if (form.usesTimedKeyframes) {
      frames.sort((a, b) => a.seconds.compareTo(b.seconds));
      return frames;
    }
    final indexed = frames.asMap().entries.toList();
    int rank(KeyframeRole role) => switch (role) {
      KeyframeRole.start => 0,
      KeyframeRole.middle => 1,
      KeyframeRole.end => 2,
    };
    indexed.sort((a, b) {
      final roleOrder = rank(a.value.role).compareTo(rank(b.value.role));
      return roleOrder == 0 ? a.key.compareTo(b.key) : roleOrder;
    });
    return indexed.map((entry) => entry.value).toList();
  }

  void updateFrame(String id, {String? source, double? seconds}) {
    form.keyframes = form.keyframes.map((frame) {
      if (frame.id != id) return frame;
      return frame.copyWith(
        source: source,
        label: source?.trim().isNotEmpty == true ? source : null,
        seconds: seconds,
      );
    }).toList();
    notifyListeners();
  }

  void removeFrame(String id) {
    form.keyframes = form.keyframes.where((frame) => frame.id != id).toList();
    notifyListeners();
  }

  Future<void> pickVideo() async {
    try {
      final asset = await _pick(type: FileType.video);
      if (asset != null) updateForm((value) => value.videoAsset = asset);
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> pickDraft() async {
    try {
      final asset = await _pick(type: FileType.any);
      if (asset != null) updateForm((value) => value.draftAsset = asset);
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  String? validate() {
    if (!hasApiKey) return 'Add your BFL API key before generating.';
    if (form.mode != VideoMode.draftEnhance && form.prompt.trim().isEmpty) {
      return 'Describe the video you want to make.';
    }
    if (form.mode == VideoMode.i2v) {
      if (form.keyframes.isEmpty) return 'Add at least one image frame.';
      if (form.keyframes.any((frame) => frame.requestSource.isEmpty)) {
        return 'Every keyframe needs an image or URL.';
      }
      if (form.requiresFixedDuration && form.autoDuration) {
        return 'Choose a fixed duration for this keyframe layout.';
      }
      if (form.usesTimedKeyframes) {
        final seconds = form.keyframes.map((frame) => frame.seconds).toList();
        if (seconds.any((value) => value < 0 || value > 20)) {
          return 'Keyframe timing must stay between 0 and 20 seconds.';
        }
        if (seconds.toSet().length != seconds.length) {
          return 'Each timed keyframe needs a unique time.';
        }
      }
    }
    if (form.mode == VideoMode.v2v &&
        form.videoAsset == null &&
        form.videoUrl.trim().isEmpty) {
      return 'Add the video you want FLUX 3 to continue.';
    }
    if (form.mode == VideoMode.draftEnhance &&
        form.draftAsset == null &&
        form.draftUrl.trim().isEmpty) {
      return 'Add a draft cache bundle or URL.';
    }
    return null;
  }

  Map<String, Object?> _buildInput() {
    if (form.mode == VideoMode.draftEnhance) {
      return <String, Object?>{
        'mode': 'draft_enhance',
        'draft_cache': form.draftAsset?.dataUrl ?? form.draftUrl.trim(),
        'resolution': form.resolution,
        'safety_tolerance': form.safetyTolerance,
      };
    }
    final common = <String, Object?>{
      'prompt': form.prompt.trim(),
      'aspect_ratio': form.aspectRatio,
      'duration': form.duration,
      'resolution': form.resolution,
      'version': 'latest',
      'generate_audio': form.generateAudio,
      'safety_tolerance': form.safetyTolerance,
      'draft': form.draft,
    };
    if (form.mode == VideoMode.i2v) {
      final frames = form.usesTimedKeyframes
          ? _orderedFrames()
                .map<Object?>(
                  (frame) => <Object?>[frame.seconds, frame.requestSource],
                )
                .toList()
          : _orderedFrames()
                .map<Object?>((frame) => frame.requestSource)
                .toList();
      return <String, Object?>{...common, 'mode': 'i2v', 'keyframes': frames};
    }
    if (form.mode == VideoMode.v2v) {
      return <String, Object?>{
        ...common,
        'mode': 'v2v',
        'start_video': form.videoAsset?.dataUrl ?? form.videoUrl.trim(),
      };
    }
    return <String, Object?>{...common, 'mode': 't2v'};
  }

  @visibleForTesting
  Map<String, Object?> buildInputForTesting() => _buildInput();

  String _uid() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${(_idCounter++).toRadixString(16)}';

  Future<void> submit() async {
    final problem = validate();
    if (problem != null) {
      showNotice(problem);
      if (!hasApiKey) unawaited(navigate(AppSection.settings));
      return;
    }
    final now = DateTime.now().toUtc();
    final estimate = currentEstimate;
    var pending = Generation(
      localId: _uid(),
      status: 'submitting',
      progress: 0,
      prompt: form.mode == VideoMode.draftEnhance
          ? 'Enhance saved FLUX 3 draft'
          : form.prompt.trim(),
      mode: form.mode,
      config: currentConfig,
      createdAt: now,
      updatedAt: now,
      estimatedCreditsMin: estimate.minimum,
      estimatedCreditsMax: estimate.maximum,
      estimateBasis: estimate.basis,
    );
    final current = snapshot;
    if (current != null) {
      snapshot = LocalSnapshot(
        generations: <Generation>[pending, ...current.generations],
        preferences: current.preferences,
        hasApiKey: current.hasApiKey,
        storage: current.storage,
      );
    }
    submitting = true;
    notifyListeners();
    showNotice('Generation sent. Clawnsole will keep an eye on it.');
    try {
      pending = await gateway.submit(
        GenerationSubmission(record: pending, input: _buildInput()),
      );
      _replaceInMemory(pending);
      if (pending.creditsAfter != null) credits = pending.creditsAfter;
    } on Object catch (error) {
      try {
        _apply(await gateway.load());
      } on Object {
        pending = pending.copyWith(
          status: 'Error',
          error: _message(error),
          updatedAt: DateTime.now().toUtc(),
        );
        _replaceInMemory(pending);
      }
      showNotice(_message(error));
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void _replaceInMemory(Generation generation) {
    final current = snapshot;
    if (current == null) return;
    final items = List<Generation>.from(current.generations);
    final index = items.indexWhere(
      (item) => item.localId == generation.localId,
    );
    if (index >= 0) {
      items[index] = generation;
    } else {
      items.insert(0, generation);
    }
    snapshot = LocalSnapshot(
      generations: items,
      preferences: current.preferences,
      hasApiKey: current.hasApiKey,
      storage: current.storage,
    );
    notifyListeners();
  }

  Future<void> pollWorking() async {
    if (_polling || !hasApiKey) return;
    final now = DateTime.now().toUtc();
    final working = generations.where((item) {
      if (!item.canCheckStatus || _statusChecks.contains(item.localId)) {
        return false;
      }
      final needsRetention =
          item.isReady &&
          item.resultAsset == null &&
          !_retentionAttempts.contains(item.localId);
      return needsRetention || (item.isWorking && item.isStatusCheckDue(now));
    }).toList();
    if (working.isEmpty) return;
    _polling = true;
    try {
      for (final item in working) {
        if (item.isReady) _retentionAttempts.add(item.localId);
        try {
          final updated = await gateway.poll(item);
          _replaceInMemory(updated);
          if (updated.isReady) {
            showNotice('Your film is ready to watch and save.');
          } else if (!item.isFailed && updated.isFailed) {
            showNotice(
              'Generation needs attention: ${updated.error ?? updated.statusLabel}',
            );
          }
        } on Object catch (error) {
          final message = _message(error);
          if (!RegExp(
            '429|active request',
            caseSensitive: false,
          ).hasMatch(message)) {
            _replaceInMemory(
              item.copyWith(
                lastCheckedAt: DateTime.now().toUtc(),
                statusCheckCount: item.statusCheckCount + 1,
                consecutiveCheckFailures: item.consecutiveCheckFailures + 1,
                lastCheckError: message,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> checkStatus(Generation item) async {
    if (!item.canCheckStatus) {
      showNotice('This generation has no provider status URL to check.');
      return;
    }
    if (!_statusChecks.add(item.localId)) return;
    notifyListeners();
    try {
      final updated = await gateway.poll(item);
      _replaceInMemory(updated);
      if (updated.lastCheckError != null) {
        showNotice('Status check failed: ${updated.lastCheckError}');
      } else if (updated.isReady) {
        showNotice('BFL reports that this film is ready.');
      } else if (updated.isFailed) {
        showNotice(updated.error ?? 'BFL reports ${updated.statusLabel}.');
      } else {
        showNotice('BFL reports ${updated.statusLabel.toLowerCase()}.');
      }
    } on Object catch (error) {
      showNotice('Status check failed: ${_message(error)}');
    } finally {
      _statusChecks.remove(item.localId);
      notifyListeners();
    }
  }

  Future<void> refreshCredits() async {
    if (!hasApiKey || refreshingCredits) return;
    refreshingCredits = true;
    creditError = null;
    notifyListeners();
    try {
      credits = await gateway.getCredits();
    } on Object catch (error) {
      creditError = _message(error);
    } finally {
      refreshingCredits = false;
      notifyListeners();
    }
  }

  Future<double> verifyKey(String candidate) =>
      gateway.verifyKey(candidate.trim().isEmpty ? null : candidate);

  Future<void> saveKey(String value) async {
    _apply(await gateway.setApiKey(value));
    credits = null;
    unawaited(refreshCredits());
    showNotice('API key saved locally.');
  }

  Future<void> removeKey() async {
    _apply(await gateway.clearApiKey());
    credits = null;
    showNotice('API key removed from local data.');
  }

  Future<void> deleteGeneration(String localId) async {
    _apply(await gateway.deleteGeneration(localId));
    showNotice('Generation record removed.');
  }

  Future<void> clearHistory() async {
    _apply(await gateway.clearHistory());
    showNotice('Generation history cleared.');
  }

  Future<void> clearPreferences() async {
    _apply(await gateway.clearPreferences());
    showNotice('Saved preferences reset.');
  }

  Future<void> clearAll() async {
    _apply(await gateway.clearAll());
    credits = null;
    showNotice('Clawnsole’s local data was removed.');
  }

  Future<PickedAsset> _retainedAsset(AssetReference reference) async =>
      PickedAsset(
        name: reference.label,
        bytes: await gateway.readAsset(reference),
        mimeType: reference.contentType ?? 'application/octet-stream',
        retained: reference,
      );

  Future<void> _restoreGenerationSettings(
    Generation item, {
    bool includePrompt = false,
  }) async {
    final retainedFrames = <KeyframeDraft>[];
    for (final frame in item.config.keyframes ?? const <KeyframeLabel>[]) {
      final reference = frame.source;
      PickedAsset? asset;
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(reference!);
        } on Object {
          // Keep the saved role and timing even if its retained file moved.
        }
      }
      retainedFrames.add(
        KeyframeDraft(
          id: _uid(),
          label: frame.label,
          role: frame.role,
          source: reference?.kind == 'remote' ? reference!.value : '',
          seconds:
              frame.seconds ??
              switch (frame.role) {
                KeyframeRole.start => 0,
                KeyframeRole.middle =>
                  item.config.duration is num
                      ? (item.config.duration as num).toDouble() / 2
                      : 4,
                KeyframeRole.end =>
                  item.config.duration is num
                      ? (item.config.duration as num).toDouble()
                      : 8,
              },
          asset: asset,
          retained: reference,
        ),
      );
    }
    PickedAsset? retainedVideo;
    if (item.mode == VideoMode.v2v && item.config.source?.isLocal == true) {
      try {
        retainedVideo = await _retainedAsset(item.config.source!);
      } on Object {
        // Preserve the rest of the last-used settings when an asset is gone.
      }
    }
    form
      ..mode = item.mode == VideoMode.draftEnhance ? VideoMode.t2v : item.mode
      ..prompt = includePrompt && item.mode != VideoMode.draftEnhance
          ? item.prompt
          : form.prompt
      ..aspectRatio = item.config.aspectRatio
      ..autoDuration = item.config.duration == 'auto'
      ..durationSeconds = item.config.duration is num
          ? (item.config.duration as num).toInt()
          : form.durationSeconds
      ..resolution = item.config.resolution
      ..generateAudio = item.config.generateAudio
      ..safetyTolerance = item.config.safetyTolerance
      ..draft = item.config.draft
      ..exactTiming = item.config.exactTiming
      ..keyframes = retainedFrames
      ..videoAsset = retainedVideo
      ..videoUrl =
          item.mode == VideoMode.v2v && item.config.source?.kind == 'remote'
          ? item.config.source!.value
          : ''
      ..draftAsset = null
      ..draftUrl = '';
    if (form.requiresFixedDuration) form.autoDuration = false;
    notifyListeners();
  }

  Future<void> reuse(Generation item) async {
    try {
      await _restoreGenerationSettings(item, includePrompt: true);
    } on Object catch (error) {
      showNotice(_message(error));
    }
    await navigate(AppSection.create);
    showNotice('Prompt, settings, and retained references copied.');
  }

  void enhance(Generation item) {
    if (item.draftCacheUrl == null) return;
    form
      ..mode = VideoMode.draftEnhance
      ..autoDuration = item.config.duration == 'auto'
      ..durationSeconds = item.config.duration is num
          ? (item.config.duration as num).toInt()
          : form.durationSeconds
      ..resolution = 'fhd'
      ..generateAudio = item.config.generateAudio
      ..draft = false
      ..draftAsset = null
      ..draftUrl = item.draftCacheUrl!;
    unawaited(navigate(AppSection.create));
  }

  Future<String?> saveVideo(
    Generation item, {
    VideoSaveDestination destination = VideoSaveDestination.files,
  }) async {
    if (item.resultAsset == null && item.resultUrl == null) {
      throw StateError('This video is not available.');
    }
    final bytes = item.resultAsset != null
        ? await gateway.readAsset(item.resultAsset!)
        : await gateway.downloadMedia(item.resultUrl!);
    final baseName =
        'clawnsole-${item.createdAt.toIso8601String().substring(0, 10)}-'
        '${item.localId.substring(0, item.localId.length.clamp(0, 6))}';
    if (destination == VideoSaveDestination.photos) {
      await gateway.saveVideoToPhotoLibrary(bytes, '$baseName.mp4');
      showNotice('Video saved to Photos.');
      return null;
    }
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save Clawnsole video',
      fileName: '$baseName.mp4',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const <String>['mp4'],
    );
    if (location == null) {
      showNotice(
        kIsWeb
            ? 'Download started. Choose a location when your browser or desktop app asks.'
            : 'Save canceled.',
      );
      return null;
    }
    showNotice('Video saved to $location');
    return location;
  }

  Future<Uri?> generationMediaUri(Generation item) async {
    if (item.resultAsset != null) return gateway.assetUri(item.resultAsset!);
    return item.resultUrl == null ? null : gateway.mediaUri(item.resultUrl!);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _creditTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }
}

enum VideoSaveDestination { photos, files }

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
