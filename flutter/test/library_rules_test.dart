import 'package:clawnsole/core/library_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleanLibraryTags trims, strips hashes, dedupes, and caps', () {
    final tags = cleanLibraryTags(<String>[
      ' #Noir ',
      'noir',
      '',
      'a' * 29,
      ...List<String>.generate(20, (index) => 'tag$index'),
    ]);
    expect(tags.first, 'Noir');
    expect(tags.where((tag) => tag.toLowerCase() == 'noir'), hasLength(1));
    expect(tags.any((tag) => tag.length > maxLibraryTagLength), isFalse);
    expect(tags, hasLength(maxLibraryTags));
  });

  test('folder and reference names respect their length rules', () {
    expect(isValidLibraryFolderName('  Client work  '), isTrue);
    expect(isValidLibraryFolderName('   '), isFalse);
    expect(isValidLibraryFolderName('x' * 49), isFalse);
    expect(isValidSavedReferenceName('x' * 80), isTrue);
    expect(isValidSavedReferenceName('x' * 81), isFalse);
    expect(libraryFolderNameRule, contains('48'));
    expect(savedReferenceNameRule, contains('80'));
  });
}
