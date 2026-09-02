/// Validation rules shared by every persistence entry point (the in-app
/// controller, the direct gateway, and the Electron companion) so one path
/// can never persist what another rejects.
library;

const int maxLibraryTagLength = 28;
const int maxLibraryTags = 12;
const int maxLibraryFolderNameLength = 48;
const int maxSavedReferenceNameLength = 80;

/// Normalizes user-entered tags: trims, strips leading `#`, drops empties and
/// over-long values, de-duplicates case-insensitively, and caps the count.
List<String> cleanLibraryTags(Iterable<String> input) {
  final tags = <String>[];
  final seen = <String>{};
  for (final value in input) {
    final clean = value.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    final key = clean.toLowerCase();
    if (clean.isEmpty || clean.length > maxLibraryTagLength) continue;
    if (!seen.add(key)) continue;
    tags.add(clean);
    if (tags.length == maxLibraryTags) break;
  }
  return tags;
}

/// Whether [name] is an acceptable folder name once trimmed.
bool isValidLibraryFolderName(String name) {
  final clean = name.trim();
  return clean.isNotEmpty && clean.length <= maxLibraryFolderNameLength;
}

/// Whether [name] is an acceptable saved-reference name once trimmed.
bool isValidSavedReferenceName(String name) {
  final clean = name.trim();
  return clean.isNotEmpty && clean.length <= maxSavedReferenceNameLength;
}

const String libraryFolderNameRule =
    'Folder names must be between 1 and $maxLibraryFolderNameLength characters.';
const String savedReferenceNameRule =
    'Reference names must be between 1 and $maxSavedReferenceNameLength characters.';
