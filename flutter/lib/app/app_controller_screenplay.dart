part of 'app_controller.dart';

final _characterReferenceExtension = RegExp(
  r'\.(?:jpe?g|png|webp|gif|heic|heif|avif|bmp|tiff?|mp4|mov|webm|m4v|avi|mkv)$',
  caseSensitive: false,
);

extension ScreenplayAuthoring on AppController {
  String characterNameForDraft(MediaReferenceDraft draft) =>
      form.draftCharacterNames[draft.id] ??
      savedReferences
          .where((item) => item.id == draft.savedReferenceId)
          .firstOrNull
          ?.characterName ??
      '';

  List<String> get screenplayCharacterNames => {
    if (form.screenplayMode) ...screenplayCharacters(form.prompt),
    ...form.screenplayCharacterAliases.keys,
    ..._defaultCharacterReferences.keys,
  }.toList()..sort();

  /// Script names remain stable when only the footer's casting name is edited.
  List<String> get scriptCharacterNames => {
    if (form.screenplayMode) ...screenplayCharacters(form.prompt),
    ...form.screenplayCharacterAliases.keys,
    ...screenplayMappings(form.prompt).keys.where(
      (name) => !form.screenplayCharacterAliases.values.contains(name),
    ),
    if (form.screenplayMode)
      ..._defaultCharacterReferences.keys.where(
        (name) =>
            !form.screenplayCharacterAliases.values.contains(name) &&
            screenplayMentionsCharacter(
              form.prompt,
              name,
              caseSensitive: false,
            ),
      ),
  }.toList()..sort();

  String characterMappingName(String scriptName) {
    final name = normalizeCharacterName(scriptName);
    return form.screenplayCharacterAliases[name] ?? name;
  }

  /// Editable casting text wins over library defaults, including an explicit
  /// removal. Defaults can still be previewed before a character speaks or the
  /// first script edit triggers automatic attachment.
  List<String> characterMappingReferences(String scriptName) {
    final name = normalizeCharacterName(scriptName);
    final mappingName = characterMappingName(name);
    final mapped = screenplayMappings(form.prompt)[mappingName];
    if (mapped != null) return mapped;
    if (_hasExplicitCharacterMapping(name)) return const [];
    return _defaultCharacterReferences[mappingName] ?? const [];
  }

  bool _hasExplicitCharacterMapping(String name, {Set<String>? mappedNames}) {
    final mappingName = characterMappingName(name);
    return form.screenplayCharacterAliases.containsKey(name) ||
        form.screenplayLinkedCharacters.contains(name) ||
        form.screenplayLinkedCharacters.contains(mappingName) ||
        (mappedNames ?? screenplayMappings(form.prompt).keys.toSet()).contains(
          mappingName,
        );
  }

  /// Match only known visual-reference names, never guessed capitalized words.
  /// An explicit character assignment takes precedence over a card/file name.
  Map<String, List<String>> get _defaultCharacterReferences {
    final result = <String, List<String>>{};
    void add(String characterName, String referenceName) {
      var name = normalizeCharacterName(characterName);
      if (name.isEmpty) {
        name = normalizeCharacterName(
          referenceName.replaceFirst(_characterReferenceExtension, ''),
        );
      }
      if (name.isEmpty || screenplayCharacterNameProblem(name) != null) return;
      final references = result.putIfAbsent(name, () => []);
      if (!references.contains(referenceName)) references.add(referenceName);
    }

    final attachedSavedIds = form.references
        .map((draft) => draft.savedReferenceId)
        .toSet();
    for (final saved in savedReferences) {
      if (!saved.hidden &&
          saved.kind != MediaReferenceKind.audio &&
          !attachedSavedIds.contains(saved.id)) {
        add(saved.characterName ?? '', saved.name);
      }
    }
    for (final draft in form.references) {
      if (draft.kind != MediaReferenceKind.audio) {
        add(characterNameForDraft(draft), referencePromptName(draft));
      }
    }
    return result;
  }

  /// Explicit cast edits also work in plaintext. Saved card assignments stay
  /// library defaults; a script may cast several media references per character.
  Future<String?> saveCharacterMapping({
    required String scriptName,
    required String name,
    required List<String> referenceNames,
    bool renameInScript = false,
  }) async {
    if (!selectedModel.supportsCharacterReferences) {
      return 'Choose a model that supports image or video references to cast characters.';
    }
    final tab = activeComposerTab;
    scriptName = normalizeCharacterName(scriptName);
    final normalized = normalizeCharacterName(name);
    final problem = screenplayCharacterNameProblem(normalized);
    if (normalized.isEmpty) return 'Enter a character name.';
    if (problem != null) return problem;
    final previous = characterMappingName(scriptName);
    if (scriptCharacterNames.any(
      (other) =>
          other != scriptName &&
          (characterMappingName(other) == normalized || other == normalized),
    )) {
      return 'That name is already used by another character in this script.';
    }
    final missing = <SavedReference>[];
    for (final refName in referenceNames.toSet()) {
      final attached = form.references
          .where((draft) => referencePromptName(draft) == refName)
          .firstOrNull;
      if (attached != null) {
        if (attached.kind == MediaReferenceKind.audio) {
          return 'Choose an image or video reference to cast a character.';
        }
        continue;
      }
      final saved = savedReferences
          .where(
            (item) =>
                !item.hidden &&
                item.name == refName &&
                item.kind != MediaReferenceKind.audio,
          )
          .firstOrNull;
      if (saved == null) {
        return '“$refName” is unavailable. Choose another reference.';
      }
      missing.add(saved);
    }
    for (final kind in MediaReferenceKind.values) {
      if (form.referenceCount(kind) +
              missing.where((item) => item.kind == kind).length >
          referenceLimit(kind)) {
        return 'This model cannot attach that many ${kind.pluralLabel}. Remove a reference or choose a compatible model.';
      }
    }
    if (selectedModel.maxTotalReferences != null &&
        form.references.length + missing.length >
            selectedModel.maxTotalReferences!) {
      return 'This model’s reference limit has been reached.';
    }
    for (final saved in missing) {
      await _inComposerTab(
        tab,
        () => addReferenceCandidates(saved.kind, [_screenplayCandidate(saved)]),
      );
    }
    return _inComposerTab(tab, () {
      if (referenceNames.any(
        (name) =>
            !form.references.any((draft) => referencePromptName(draft) == name),
      )) {
        return 'A reference could not be loaded. Please try again.';
      }
      form.prompt = replaceScreenplayMapping(
        form.prompt,
        previous,
        normalized,
        referenceNames,
      );
      if (renameInScript) {
        form.prompt = renameScreenplayCharacter(
          form.prompt,
          scriptName,
          normalized,
          caseSensitive: false,
        );
        form.screenplayCharacterAliases.remove(scriptName);
        form.screenplayCharacterAliases[normalized] = normalized;
      } else if (normalized != scriptName) {
        form.screenplayCharacterAliases[scriptName] = normalized;
      } else {
        form.screenplayCharacterAliases[scriptName] = normalized;
      }
      form.screenplayLinkedCharacters.addAll([
        scriptName,
        previous,
        normalized,
      ]);
      _invalidateProviderEstimate();
      _scheduleComposerTabsSave(touched: tab);
      notifyListeners();
      return null;
    });
  }

  String? characterNameProblem(
    String value, {
    String? excludeDraftId,
    String? excludeSavedReferenceId,
  }) {
    final problem = screenplayCharacterNameProblem(value);
    if (problem != null) return problem;
    final name = normalizeCharacterName(value);
    if (name.isEmpty) return null;
    final duplicate =
        savedReferences.any(
          (item) =>
              item.id != excludeSavedReferenceId &&
              normalizeCharacterName(item.characterName ?? '') == name,
        ) ||
        _composerTabs.any(
          (tab) => tab.form.references.any(
            (item) =>
                item.id != excludeDraftId &&
                (excludeSavedReferenceId == null ||
                    item.savedReferenceId != excludeSavedReferenceId) &&
                normalizeCharacterName(
                      tab.form.draftCharacterNames[item.id] ?? '',
                    ) ==
                    name,
          ),
        );
    return duplicate
        ? 'Character names must be unique across references.'
        : null;
  }

  Future<bool> setDraftCharacterName(String id, String value) async {
    final tab = activeComposerTab;
    final draft = tab.form.references
        .where((item) => item.id == id)
        .firstOrNull;
    if (draft == null) return false;
    final name = normalizeCharacterName(value);
    final problem = characterNameProblem(
      name,
      excludeDraftId: id,
      excludeSavedReferenceId: draft.savedReferenceId,
    );
    if (problem != null) {
      showNotice(problem);
      return false;
    }
    final previous = characterNameForDraft(draft);
    final saved = savedReferences
        .where((item) => item.id == draft.savedReferenceId)
        .firstOrNull;
    if (saved != null && gateway is ReferenceLibraryGateway) {
      try {
        _apply(
          await (gateway as ReferenceLibraryGateway).saveReference(
            saved.copyWith(
              characterName: name,
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
        );
      } on Object catch (error) {
        showNotice(_message(error));
        return false;
      }
    }
    _inComposerTab(tab, () {
      if (saved == null) {
        form.draftCharacterNames[id] = name;
      } else {
        form.draftCharacterNames.remove(id);
        _savedCharacterChanged(saved.id, previous, name);
      }
      final oldMapping = '$previous: @${referencePromptName(draft)}';
      form.prompt = form.prompt
          .split('\n')
          .where((line) => line.trim() != oldMapping)
          .join('\n');
      form.screenplayLinkedCharacters.remove(name);
      _syncScreenplayReferences();
      _scheduleComposerTabsSave();
    });
    notifyListeners();
    return true;
  }

  void _savedCharacterChanged(String savedId, String previous, String name) {
    for (final tab in _composerTabs) {
      _inComposerTab(tab, () {
        for (final draft in form.references.where(
          (item) => item.savedReferenceId == savedId,
        )) {
          form.draftCharacterNames.remove(draft.id);
          final oldMapping = '$previous: @${referencePromptName(draft)}';
          form.prompt = form.prompt
              .split('\n')
              .where((line) => line.trim() != oldMapping)
              .join('\n');
        }
        form.screenplayLinkedCharacters.remove(name);
        _syncScreenplayReferences();
        _scheduleComposerTabsSave(touched: tab);
      });
    }
  }

  void setScreenplayMode(bool enabled) {
    updateForm((form) {
      form.screenplayMode = enabled;
      if (enabled) form.prompt = formatScreenplay(form.prompt);
    });
  }

  ReferenceCandidate _screenplayCandidate(SavedReference saved) =>
      ReferenceCandidate(
        id: saved.id,
        name: saved.name,
        kind: saved.kind,
        asset: saved.asset,
        thumbnailAsset: saved.thumbnailAsset,
        createdAt: saved.createdAt,
        storage: saved.storage,
        durationSeconds: saved.durationSeconds,
      );

  /// Insert once as ordinary editable text. Remembering the character means
  /// deleting or editing a mapping never causes it to spring back on typing.
  void syncScreenplayCharacterMappings() {
    final prompt = form.prompt;
    final references = form.references.length;
    final linked = form.screenplayLinkedCharacters.length;
    _syncScreenplayReferences();
    if (prompt != form.prompt ||
        references != form.references.length ||
        linked != form.screenplayLinkedCharacters.length) {
      _invalidateProviderEstimate();
      _scheduleComposerTabsSave();
      notifyListeners();
    }
  }

  void _syncScreenplayReferences() {
    if (!form.screenplayMode || !selectedModel.supportsCharacterReferences) {
      return;
    }
    final names = _defaultCharacterReferences;
    final mappedNames = screenplayMappings(form.prompt).keys.toSet();
    for (final entry in names.entries) {
      final name = entry.key;
      if (_hasExplicitCharacterMapping(name, mappedNames: mappedNames)) {
        // Remember restored/manual footers too, so deleting one is final.
        form.screenplayLinkedCharacters.add(name);
        continue;
      }
      if (!screenplayMentionsCharacter(
        form.prompt,
        name,
        caseSensitive: false,
      )) {
        continue;
      }
      final attached = <String>[];
      for (final referenceName in entry.value) {
        var draft = form.references
            .where((item) => referencePromptName(item) == referenceName)
            .firstOrNull;
        final saved = savedReferences
            .where((item) => !item.hidden && item.name == referenceName)
            .firstOrNull;
        if (draft == null && saved != null) {
          // Respect the current model's capability and available capacity.
          if (referenceLimit(saved.kind) <= form.referenceCount(saved.kind) ||
              (selectedModel.maxTotalReferences != null &&
                  form.references.length >=
                      selectedModel.maxTotalReferences!)) {
            continue;
          }
          // Attachment happens synchronously before background hydration. That
          // operation captures this tab so a later tab switch is safe.
          unawaited(
            addReferenceCandidates(saved.kind, [_screenplayCandidate(saved)]),
          );
          draft = form.references
              .where((item) => item.savedReferenceId == saved.id)
              .firstOrNull;
        }
        if (draft != null) attached.add(referencePromptName(draft));
      }
      if (attached.isEmpty) continue;
      form.screenplayLinkedCharacters.add(name);
      final mappingName = characterMappingName(name);
      form.prompt = replaceScreenplayMapping(
        form.prompt,
        mappingName,
        mappingName,
        attached,
      );
    }
  }
}
