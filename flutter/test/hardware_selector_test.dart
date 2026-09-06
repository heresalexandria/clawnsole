import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:clawnsole/ui/hardware_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _chevron = ValueKey<String>('hardware-selector-chevron');
const _frame = ValueKey<String>('hardware-selector-frame');

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

HardwareSelectorFramePainter _framePainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(_frame)).painter!
        as HardwareSelectorFramePainter;

HardwareSelectorKeyPainter _keyPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(_chevron)).painter!
        as HardwareSelectorKeyPainter;

void main() {
  testWidgets('renders its readout and the chevron key that opens the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const HardwareSelector(child: Text('Black Forest Labs'))),
    );

    expect(find.text('Black Forest Labs'), findsOneWidget);
    expect(find.byKey(_chevron), findsOneWidget);
  });

  testWidgets('stands at the console control height, hugging and stretched', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HardwareSelector(
                  key: ValueKey<String>('hug'),
                  child: Text('Krea'),
                ),
              ],
            ),
            SizedBox(
              width: 400,
              child: HardwareSelector(
                key: ValueKey<String>('stretch'),
                child: Text('Krea'),
              ),
            ),
          ],
        ),
      ),
    );

    final hug = tester.getSize(find.byKey(const ValueKey<String>('hug')));
    final stretched = tester.getSize(
      find.byKey(const ValueKey<String>('stretch')),
    );
    expect(hug.height, kConsoleControlHeight);
    expect(stretched.height, kConsoleControlHeight);
    // Hugging keeps the plate to its content (never below its floor); a tight
    // parent widens the window instead.
    expect(hug.width, lessThan(400));
    expect(hug.width, greaterThanOrEqualTo(220));
    expect(stretched.width, 400);
  });

  testWidgets('the chevron key stays at the right edge as the window grows', (
    tester,
  ) async {
    Future<double> keyLeftFor(double width) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: width,
            child: const HardwareSelector(child: Text('Krea')),
          ),
        ),
      );
      return tester.getRect(find.byKey(_chevron)).left;
    }

    final narrow = await keyLeftFor(300);
    final wide = await keyLeftFor(520);
    expect(wide - narrow, closeTo(220, .01));
    // Fixed size, whatever the plate does around it.
    expect(tester.getSize(find.byKey(_chevron)), const Size(30, 38));
  });

  testWidgets(
    'a very narrow parent ellipsizes the readout instead of overflowing',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 170,
            child: HardwareSelector(
              child: Text(
                'Black Forest Labs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(HardwareSelector));
      expect(size, const Size(170, kConsoleControlHeight));
      // The key keeps its place at the right edge even here.
      expect(
        tester.getRect(find.byKey(_chevron)).right,
        tester.getRect(find.byType(HardwareSelector)).right - 7,
      );
    },
  );

  testWidgets(
    'the window follows the mode: cream well on paper, pane at night',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const HardwareSelector(child: Text('Krea')),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();
      final pale = _framePainter(tester).windowColors;
      expect(pale, HardwareSelector.windowGradient(Brightness.light));
      // Light mode never puts a dark island on paper.
      for (final Color color in pale) {
        expect(color.computeLuminance(), greaterThan(.6));
      }

      await tester.pumpWidget(
        _host(
          const HardwareSelector(child: Text('Krea')),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      final smoked = _framePainter(tester).windowColors;
      expect(smoked, HardwareSelector.windowGradient(Brightness.dark));
      for (final Color color in smoked) {
        expect(color.computeLuminance(), lessThan(.05));
      }
    },
  );

  testWidgets('the readout ink is legible in both modes', (tester) async {
    for (final brightness in Brightness.values) {
      late HardwareSelectorInk ink;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              ink = HardwareSelector.inkOf(context);
              return const HardwareSelector(child: Text('Krea'));
            },
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      final window = HardwareSelector.windowGradient(brightness);
      for (final Color ground in window) {
        for (final Color text in <Color>[ink.on, ink.onMuted]) {
          final high = <double>[
            ground.computeLuminance(),
            text.computeLuminance(),
          ]..sort();
          expect(
            (high.last + .05) / (high.first + .05),
            greaterThanOrEqualTo(4.5),
            reason: '$text on $ground in $brightness',
          );
        }
      }
      // Backlit at night, plain ink on paper.
      expect(ink.glow.isNotEmpty, brightness == Brightness.dark);
    }
  });

  testWidgets('hover and press light the key without swallowing the tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        GestureDetector(
          onTap: () => taps++,
          child: const HardwareSelector(child: Text('Krea')),
        ),
      ),
    );
    expect(_keyPainter(tester).hover, 0);
    expect(_keyPainter(tester).press, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(HardwareSelector)));
    await tester.pumpAndSettle();
    expect(_keyPainter(tester).hover, 1);

    // A press sinks the key, and the enclosing gesture still gets its tap.
    final press = await tester.startGesture(
      tester.getCenter(find.byType(HardwareSelector)),
    );
    await tester.pumpAndSettle();
    expect(_keyPainter(tester).press, 1);
    await press.up();
    await tester.pumpAndSettle();
    expect(_keyPainter(tester).press, 0);
    expect(taps, 1);

    await mouse.moveTo(
      tester.getBottomRight(find.byType(HardwareSelector)) +
          const Offset(80, 80),
    );
    await tester.pumpAndSettle();
    expect(_keyPainter(tester).hover, 0);
  });

  testWidgets('an owner may drive the press state itself', (tester) async {
    await tester.pumpWidget(
      _host(const HardwareSelector(pressed: true, child: Text('Krea'))),
    );
    await tester.pumpAndSettle();
    expect(_keyPainter(tester).press, 1);
  });

  testWidgets('the semantic hint says what the control opens', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const HardwareSelector(
          semanticHint: 'Opens the provider and model menu',
          child: Text('Krea'),
        ),
      ),
    );

    expect(
      tester
          .getSemantics(find.byType(HardwareSelector))
          .hint
          .contains('Opens the provider and model menu'),
      isTrue,
    );
    handle.dispose();
  });
}
