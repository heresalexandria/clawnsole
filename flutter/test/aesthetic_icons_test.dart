import 'package:clawnsole/ui/aesthetic_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The envelope [AestheticIcon] wraps every fragment in before handing it to
/// flutter_svg. Kept here so the parse test compiles exactly what ships.
String _svgFor(String name) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="black" stroke-width="1.6" stroke-linecap="round" '
    'stroke-linejoin="round">${aestheticIconPaths[name]}</svg>';

/// The sixteen drawings that shipped first. Saved records reference icons by
/// name, so these entries must keep both their key and their exact markup.
const _originals = <String, String>{
  'sparkles': '<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z"/>',
  'sun':
      '<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
  'moon': '<path d="M20 15A9 9 0 0 1 9 3a9 9 0 1 0 11 12Z"/>',
  'star': '<path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>',
  'camera':
      '<rect x="2" y="6" width="20" height="15" rx="3"/><circle cx="12" cy="13" r="4"/><path d="m7 6 2-4h6l2 4"/>',
  'film':
      '<rect x="3" y="2" width="18" height="20" rx="2"/><path d="M7 2v20M17 2v20M3 7h4m-4 5h4m-4 5h4M17 7h4m-4 5h4m-4 5h4"/>',
  'mountain': '<path d="m2 21 8-17 5 10 3-6 5 13Zm5-10 3 2 3-2"/>',
  'leaf': '<path d="M3 21 18 6M4 17C-2 6 12 2 22 2c0 10-3 20-14 17"/>',
  'flower':
      '<circle cx="12" cy="12" r="3"/><path d="M9 9C1 2 12-2 12 7c0-9 11-5 3 2 8-7 12 4 3 3 9 0 5 11-3 3 8 8-3 12-3 3 0 9-11 5-3-3-8 8-12-3-3-3-9 1-5-10 3-3Z"/>',
  'waves':
      '<path d="M2 6q5-5 10 0t10 0M2 12q5-5 10 0t10 0M2 18q5-5 10 0t10 0"/>',
  'flame':
      '<path d="M13 2c2 8-7 7-5 13 3 0 5-4 5-6 10 9 4 14-2 13C0 21 3 11 7 8c0 5 2 5 2 5-2-5 3-7 4-11Z"/>',
  'cloud': '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-1 6 6 0 0 1 0 11Z"/>',
  'diamond': '<path d="m2 8 5-6h10l5 6-10 14Zm0 0h20M7 2l5 20 5-20"/>',
  'eye':
      '<path d="M1 12Q12-3 23 12 12 27 1 12Z"/><circle cx="12" cy="12" r="3"/>',
  'palette':
      '<path d="M12 2a10 10 0 1 0 0 20c5 0-2-6 3-6 9 0 9-14-3-14Z"/><circle cx="7" cy="9" r="1"/><circle cx="12" cy="6" r="1"/><circle cx="17" cy="9" r="1"/>',
  'bolt': '<path d="m14 1-12 13h9l-1 9L22 9h-9Z"/>',
};

void main() {
  test('the icon set is large and every name is stable kebab-case', () {
    expect(aestheticIconPaths.length, greaterThanOrEqualTo(64));
    final namePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
    for (final name in aestheticIconPaths.keys) {
      expect(
        namePattern.hasMatch(name),
        isTrue,
        reason: '"$name" is not lowercase kebab-case',
      );
    }
  });

  test('every fragment is stroke-only markup with no foreign elements', () {
    const banned = <String>['fill=', '<text', '<image', 'script', 'style='];
    for (final entry in aestheticIconPaths.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key} is empty');
      for (final needle in banned) {
        expect(
          entry.value.contains(needle),
          isFalse,
          reason: '${entry.key} contains "$needle"',
        );
      }
      // Only the geometric primitives the renderer envelope expects.
      final allowed = RegExp(
        r'^(<(path|circle|rect|line|polyline|ellipse)\s[^<>]*/>)+$',
      );
      expect(
        allowed.hasMatch(entry.value),
        isTrue,
        reason: '${entry.key} uses markup outside the allowed elements',
      );
    }
  });

  test('the original sixteen drawings are untouched', () {
    for (final entry in _originals.entries) {
      expect(
        aestheticIconPaths[entry.key],
        entry.value,
        reason: '${entry.key} changed; saved records reference it by name',
      );
    }
    expect(
      aestheticIconPaths['sparkles'],
      '<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z"/>',
    );
    expect(
      aestheticIconPaths['bolt'],
      '<path d="m14 1-12 13h9l-1 9L22 9h-9Z"/>',
    );
  });

  test('groups partition the icon set exactly once', () {
    expect(aestheticIconGroups, isNotEmpty);
    final seen = <String>[];
    for (final group in aestheticIconGroups.entries) {
      expect(group.value, isNotEmpty, reason: '${group.key} is empty');
      seen.addAll(group.value);
    }
    expect(
      seen.length,
      seen.toSet().length,
      reason: 'an icon appears in more than one group',
    );
    expect(seen.toSet(), aestheticIconPaths.keys.toSet());
  });

  testWidgets('every icon renders without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                for (final name in aestheticIconPaths.keys)
                  AestheticIcon(name: name, color: 0xffaf853c, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(AestheticIcon),
      findsNWidgets(aestheticIconPaths.length),
    );
  });

  // Mounting the widgets is not enough on its own: flutter_svg defers the
  // compile, so a malformed fragment never reaches takeException(). Compile
  // each one explicitly — that is what actually rejects a broken path.
  testWidgets('every fragment compiles as SVG', (tester) async {
    final failures = <String, Object>{};
    await tester.runAsync(() async {
      for (final name in aestheticIconPaths.keys) {
        try {
          await SvgStringLoader(_svgFor(name)).loadBytes(null);
        } catch (error) {
          failures[name] = error;
        }
      }
    });
    expect(failures, isEmpty, reason: 'fragments failed to parse: $failures');
  });
}
