/// The library half of character casting: names, and the saved media that
/// carries them.
///
/// A character is what Create maps a name in the direction to. Two things
/// produce that mapping today, and this file reads both:
///
/// * a saved reference's `characterName` assignment — deliberately **unique
///   across references**, enforced in `referenceCharacterAssignmentProblem`
///   at every storage boundary, so exactly one card wears a given name; and
/// * a saved reference whose file name (minus its media extension) *is* the
///   name, which Create casts alongside the named card.
///
/// So a character can hold several references while its name still belongs to
/// one of them. Editing here rewrites the assignment through
/// [AppController.updateSavedReference], which is what keeps Drive, the local
/// store, prompt tags, and the composer's cast in step. Per-draft casting —
/// `form.characterMappings` — stays on the Create screen and is untouched.
library;

import '../core/models.dart';
import '../core/screenplay.dart';
import 'app_controller.dart';

/// One character and every saved reference Create maps to its name.
class CharacterEntry {
  const CharacterEntry({
    required this.name,
    required this.references,
    required this.matched,
  });

  /// Normalized, upper-case — the form a direction is matched against.
  final String name;

  /// References carrying this assignment. One, under today's uniqueness rule.
  final List<SavedReference> references;

  /// References Create also casts under this name because their file name
  /// says so. They carry no assignment, so this tab cannot detach them —
  /// renaming the media on the Media tab is what unlinks one.
  final List<SavedReference> matched;

  /// Everything cast under the name, the named reference leading.
  List<SavedReference> get cast => <SavedReference>[...references, ...matched];

  int get count => references.length + matched.length;
}

extension CharacterLibraryEditing on AppController {
  /// Every named character, its references gathered, sorted by name.
  List<CharacterEntry> get characterLibrary {
    final named = <String, List<SavedReference>>{};
    for (final item in savedReferences) {
      if (item.hidden) continue;
      final name = normalizeCharacterName(item.characterName ?? '');
      if (name.isEmpty) continue;
      named.putIfAbsent(name, () => <SavedReference>[]).add(item);
    }
    final matched = <String, List<SavedReference>>{};
    for (final item in savedReferences) {
      final name = characterFileNameFor(item);
      if (name == null || !named.containsKey(name)) continue;
      matched.putIfAbsent(name, () => <SavedReference>[]).add(item);
    }
    int byName(SavedReference a, SavedReference b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return <CharacterEntry>[
      for (final name in named.keys.toList()..sort())
        CharacterEntry(
          name: name,
          references: named[name]!..sort(byName),
          matched: (matched[name] ?? <SavedReference>[])..sort(byName),
        ),
    ];
  }

  /// Visual references no character name has claimed, ready to be named.
  List<SavedReference> get unassignedCharacterReferences =>
      savedReferences
          .where(
            (item) =>
                !item.hidden &&
                item.kind != MediaReferenceKind.audio &&
                normalizeCharacterName(item.characterName ?? '').isEmpty,
          )
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The character [reference] is cast as by its file name alone, or null when
  /// it carries an assignment, cannot be cast, or its name is no character.
  String? characterFileNameFor(SavedReference reference) {
    if (reference.hidden || reference.kind == MediaReferenceKind.audio) {
      return null;
    }
    if (normalizeCharacterName(reference.characterName ?? '').isNotEmpty) {
      return null;
    }
    final name = normalizeCharacterName(
      characterReferenceBaseName(reference.name),
    );
    if (name.isEmpty || screenplayCharacterNameProblem(name) != null) {
      return null;
    }
    return name;
  }

  /// Every reference carrying [name], hidden ones included: the uniqueness
  /// rule counts those too, so an edit has to see them.
  List<SavedReference> characterReferencesNamed(String name) {
    final character = normalizeCharacterName(name);
    if (character.isEmpty) return const <SavedReference>[];
    return savedReferences
        .where(
          (item) =>
              normalizeCharacterName(item.characterName ?? '') == character,
        )
        .toList();
  }

  /// The reference already wearing [name], if it is not one of [allowedIds].
  /// A name belongs to one card, so this is what blocks a rename or a merge.
  SavedReference? characterNameHolder(String name, {Set<String>? allowedIds}) {
    final character = normalizeCharacterName(name);
    if (character.isEmpty) return null;
    return savedReferences
        .where(
          (item) =>
              !(allowedIds ?? const <String>{}).contains(item.id) &&
              normalizeCharacterName(item.characterName ?? '') == character,
        )
        .firstOrNull;
  }

  /// Renames a character wherever it is written. One notice for the batch.
  Future<bool> renameCharacter(String from, String to) async {
    final previous = normalizeCharacterName(from);
    final next = normalizeCharacterName(to);
    if (previous.isEmpty) return false;
    if (next.isEmpty) {
      showNotice('Enter a character name.');
      return false;
    }
    if (next == previous) return true;
    final problem = screenplayCharacterNameProblem(next);
    if (problem != null) {
      showNotice(problem);
      return false;
    }
    final ids = characterReferencesNamed(
      previous,
    ).map((item) => item.id).toSet();
    if (ids.isEmpty) {
      showNotice('$previous no longer names a reference.');
      return false;
    }
    final holder = characterNameHolder(next, allowedIds: ids);
    if (holder != null) {
      showNotice(_takenMessage(next, holder));
      return false;
    }
    var written = 0;
    for (final id in ids) {
      if (!await _writeCharacterName(id, next)) return false;
      written += 1;
    }
    showNotice('$previous renamed to $next across ${_count(written)}.');
    return true;
  }

  /// Gives [referenceIds] the character [name]. One notice for the batch.
  Future<bool> assignReferencesToCharacter(
    String name,
    Iterable<String> referenceIds,
  ) async {
    final character = normalizeCharacterName(name);
    if (character.isEmpty) {
      showNotice('Enter a character name.');
      return false;
    }
    final problem = screenplayCharacterNameProblem(character);
    if (problem != null) {
      showNotice(problem);
      return false;
    }
    final ids = referenceIds.toSet();
    final holder = characterNameHolder(character, allowedIds: ids);
    if (holder != null) {
      showNotice(_takenMessage(character, holder));
      return false;
    }
    var written = 0;
    for (final id in ids) {
      final reference = savedReferences
          .where((item) => item.id == id)
          .firstOrNull;
      if (reference == null) continue;
      if (normalizeCharacterName(reference.characterName ?? '') == character) {
        continue;
      }
      if (!await _writeCharacterName(id, character)) return false;
      written += 1;
    }
    if (written > 0) showNotice('${_count(written)} added to $character.');
    return true;
  }

  /// Takes one reference back out of its character. The media stays.
  Future<bool> unassignReference(String referenceId) async {
    final reference = savedReferences
        .where((item) => item.id == referenceId)
        .firstOrNull;
    if (reference == null) return false;
    final previous = normalizeCharacterName(reference.characterName ?? '');
    if (previous.isEmpty) return true;
    if (!await _writeCharacterName(referenceId, '')) return false;
    showNotice('“${reference.name}” is no longer $previous.');
    return true;
  }

  /// Clears a character off every reference wearing it. Never deletes media.
  Future<bool> deleteCharacter(String name) async {
    final character = normalizeCharacterName(name);
    if (character.isEmpty) return false;
    final ids = characterReferencesNamed(
      character,
    ).map((item) => item.id).toList();
    if (ids.isEmpty) return false;
    var written = 0;
    for (final id in ids) {
      if (!await _writeCharacterName(id, '')) return false;
      written += 1;
    }
    showNotice(
      '$character cleared from ${_count(written)}. The media stays in '
      'References.',
    );
    return true;
  }

  /// The Characters sheet's single write: rename, add, and release in one
  /// pass so the desk speaks once however much moved.
  ///
  /// [previousName] is the character being edited, empty for a new one.
  /// [referenceIds] is the character's membership after the edit; ids that
  /// carried the old or the new name and are missing from it are released.
  Future<bool> saveCharacter({
    required String name,
    required Iterable<String> referenceIds,
    String previousName = '',
  }) async {
    final next = normalizeCharacterName(name);
    final previous = normalizeCharacterName(previousName);
    if (next.isEmpty) {
      showNotice('Enter a character name.');
      return false;
    }
    final problem = screenplayCharacterNameProblem(next);
    if (problem != null) {
      showNotice(problem);
      return false;
    }
    final keep = referenceIds.toSet();
    final current = <String>{
      ...characterReferencesNamed(previous).map((item) => item.id),
      ...characterReferencesNamed(next).map((item) => item.id),
    };
    final holder = characterNameHolder(next, allowedIds: {...keep, ...current});
    if (holder != null) {
      showNotice(_takenMessage(next, holder));
      return false;
    }
    // Release first: it frees the name for whichever reference takes it next,
    // which is what makes swapping a character's portrait a single save.
    final released = current.where((id) => !keep.contains(id)).toList();
    for (final id in released) {
      if (!await _writeCharacterName(id, '')) return false;
    }
    var renamed = 0;
    var added = 0;
    for (final id in keep) {
      final reference = savedReferences
          .where((item) => item.id == id)
          .firstOrNull;
      if (reference == null) continue;
      final held = normalizeCharacterName(reference.characterName ?? '');
      if (held == next) continue;
      if (!await _writeCharacterName(id, next)) return false;
      if (held == previous && previous.isNotEmpty) {
        renamed += 1;
      } else {
        added += 1;
      }
    }
    final parts = <String>[
      if (renamed > 0 && previous.isNotEmpty && previous != next)
        '$previous renamed to $next across ${_count(renamed)}'
      else if (renamed > 0)
        '$next updated',
      if (added > 0) '${_count(added)} added to $next',
      if (released.isNotEmpty) '${_count(released.length)} released',
    ];
    if (parts.isNotEmpty) showNotice('${parts.join(', ')}.');
    return true;
  }

  /// Opens the References desk on its Characters tab.
  Future<void> openCharacterLibrary() async {
    referencesTab = ReferencesTab.characters;
    await navigate(AppSection.references);
  }

  String _takenMessage(String name, SavedReference holder) =>
      '$name already names “${holder.name}”. A character name belongs to one '
      'reference — release that one first, or choose another name.';

  String _count(int value) => value == 1 ? '1 reference' : '$value references';

  /// One assignment write. [name] empty clears it.
  ///
  /// Every mutation here is a batch of these, and `updateSavedReference` ends
  /// each one with its own “Reference updated.” The batch speaks once instead:
  /// the snackbar is raised from a build, and dropping the notice in the
  /// microtask that resumes this method runs before any frame can paint it.
  Future<bool> _writeCharacterName(String referenceId, String name) async {
    final reference = savedReferences
        .where((item) => item.id == referenceId)
        .firstOrNull;
    if (reference == null) return false;
    final saved = await updateSavedReference(
      reference,
      name: reference.name,
      characterName: name,
      folderId: reference.folderId,
      tags: reference.tags,
    );
    if (saved) {
      notice = null;
      noticeAction = null;
    }
    return saved;
  }
}
