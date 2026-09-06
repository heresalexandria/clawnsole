part of 'app_controller.dart';

final _characterReferenceExtension = RegExp(
  r'\.(?:jpe?g|png|webp|gif|heic|heif|avif|bmp|tiff?|mp4|mov|webm|m4v|avi|mkv)$',
  caseSensitive: false,
);

/// A reference name with its media extension trimmed off, the form a file name
/// is matched against a character in. The cast chooser sorts by the same rule,
/// so "Vinny.mp4" reads as a match for VINNY there too.
String characterReferenceBaseName(String name) =>
    name.replaceFirst(_characterReferenceExtension, '');

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

  /// Script names remain stable when only the cast's casting name is edited.
  List<String> get scriptCharacterNames => {
    if (form.screenplayMode) ...screenplayCharacters(form.prompt),
    ...form.screenplayCharacterAliases.keys,
    ...form.characterMappings.keys.where(
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

  /// The script name a cast entry belongs to, so a chip in the Cast row opens
  /// the same editor the Characters dialog does. Falls back to the cast name
  /// itself, which is what an added-by-hand character is filed under.
  String castScriptName(String mappingName) {
    final name = normalizeCharacterName(mappingName);
    return scriptCharacterNames.firstWhere(
      (script) => characterMappingName(script) == name,
      orElse: () => name,
    );
  }

  /// The casting block as it will be appended at submission.
  List<String> get castLines => screenplayCastLines(form.characterMappings);

  /// The direction plus its casting block. Everything that measures or sends
  /// the prompt — the counter, the limit, the estimate, the submitted input —
  /// goes through here (or [generationPrompt]), so a cast counts against the
  /// character limit without ever appearing in the editable text.
  String get promptWithCast {
    final lines = castLines;
    if (lines.isEmpty) return form.prompt;
    final direction = form.prompt.trimRight();
    final block = lines.join('\n');
    return direction.isEmpty ? block : '$direction\n\n$block';
  }

  /// Lifts casting lines that arrived inside the prompt — a legacy workspace,
  /// a reused film, a paste, an AI Rewrite — into [form.characterMappings] and
  /// strips them from the editable text. Returns whether anything moved.
  bool absorbPromptMappings() {
    final absorbed = screenplayMappings(form.prompt);
    if (absorbed.isEmpty) return false;
    form.prompt = stripScreenplayMappings(form.prompt);
    for (final entry in absorbed.entries) {
      final name = normalizeCharacterName(entry.key);
      if (name.isEmpty) continue;
      if (entry.value.isEmpty) {
        form.characterMappings.remove(name);
      } else {
        form.characterMappings[name] = entry.value.toSet().toList();
      }
      // A line that was written down is an explicit choice, exactly as it was
      // when the prompt held it: automatic casting must not undo it.
      form.screenplayLinkedCharacters.add(name);
    }
    return true;
  }

  /// The cast wins over library defaults, including an explicit removal.
  /// Defaults can still be previewed before a character speaks or the first
  /// script edit triggers automatic attachment.
  List<String> characterMappingReferences(String scriptName) {
    final name = normalizeCharacterName(scriptName);
    final mappingName = characterMappingName(name);
    final mapped = form.characterMappings[mappingName];
    if (mapped != null) return mapped;
    if (_hasExplicitCharacterMapping(name)) return const [];
    return _defaultCharacterReferences[mappingName] ?? const [];
  }

  bool _hasExplicitCharacterMapping(String name, {Set<String>? mappedNames}) {
    final mappingName = characterMappingName(name);
    return form.screenplayCharacterAliases.containsKey(name) ||
        form.screenplayLinkedCharacters.contains(name) ||
        form.screenplayLinkedCharacters.contains(mappingName) ||
        (mappedNames ?? form.characterMappings.keys.toSet()).contains(
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
  /// library defaults; a script may cast several media references per
  /// character. The choice lands in [form.characterMappings], never in the
  /// editable prompt.
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
      final chosen = referenceNames.toSet().toList();
      form.characterMappings.remove(previous);
      if (chosen.isEmpty) {
        form.characterMappings.remove(normalized);
      } else {
        form.characterMappings[normalized] = chosen;
      }
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
      _dropDefaultCastEntry(previous, referencePromptName(draft));
      form.screenplayLinkedCharacters.remove(name);
      _syncScreenplayReferences();
      _scheduleComposerTabsSave();
    });
    notifyListeners();
    return true;
  }

  /// Forgets the cast entry a character name change made stale — the one this
  /// reference was the whole of. A cast assembled by hand from several media
  /// is the director's, so it survives a rename of one of its members.
  void _dropDefaultCastEntry(String previous, String referenceName) {
    final name = normalizeCharacterName(previous);
    final current = form.characterMappings[name];
    if (current != null &&
        current.length == 1 &&
        current.single == referenceName) {
      form.characterMappings.remove(name);
    }
  }

  /// Drops [referenceName] from every cast entry, emptied entries with it.
  /// The characters stay linked so automatic casting does not put them back.
  void _removeCastReference(String referenceName) {
    for (final name in form.characterMappings.keys.toList()) {
      final current = form.characterMappings[name]!;
      if (!current.contains(referenceName)) continue;
      final remaining = current.where((item) => item != referenceName).toList();
      form.screenplayLinkedCharacters.add(name);
      if (remaining.isEmpty) {
        form.characterMappings.remove(name);
      } else {
        form.characterMappings[name] = remaining;
      }
    }
  }

  /// Follows a reference rename into the cast, so a renamed card keeps the
  /// characters it was cast as.
  void _renameCastReference(String previous, String name) {
    if (previous == name) return;
    final renamed = <String, List<String>>{
      for (final entry in form.characterMappings.entries)
        entry.key: entry.value
            .map((item) => item == previous ? name : item)
            .toList(),
    };
    form.characterMappings
      ..clear()
      ..addAll(renamed);
  }

  void _savedCharacterChanged(String savedId, String previous, String name) {
    for (final tab in _composerTabs) {
      _inComposerTab(tab, () {
        for (final draft in form.references.where(
          (item) => item.savedReferenceId == savedId,
        )) {
          form.draftCharacterNames.remove(draft.id);
          _dropDefaultCastEntry(previous, referencePromptName(draft));
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

  /// Cast once. Remembering the character means deleting or editing a cast
  /// entry never causes it to spring back on the next keystroke.
  void syncScreenplayCharacterMappings() {
    final prompt = form.prompt;
    final cast = castLines.join('\n');
    final references = form.references.length;
    final linked = form.screenplayLinkedCharacters.length;
    // Self-healing for any path that seeded the prompt with casting lines.
    absorbPromptMappings();
    _syncScreenplayReferences();
    if (prompt != form.prompt ||
        cast != castLines.join('\n') ||
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
    final mappedNames = form.characterMappings.keys.toSet();
    for (final entry in names.entries) {
      final name = entry.key;
      if (_hasExplicitCharacterMapping(name, mappedNames: mappedNames)) {
        // Remember restored/manual cast entries too, so deleting one is final.
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
      form.characterMappings[characterMappingName(name)] = attached;
    }
  }
}
