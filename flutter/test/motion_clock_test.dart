import 'package:clawnsole/ui/motion_clock.dart';
import 'package:clawnsole/ui/motion_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A surface driven by a [MotionClock]: counts how many times it painted.
class _ClockHost extends StatefulWidget {
  const _ClockHost({super.key});

  @override
  State<_ClockHost> createState() => _ClockHostState();
}

class _ClockHostState extends State<_ClockHost> {
  final MotionClock clock = MotionClock();
  int paints = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clock.attach(context);
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(120, 80),
      painter: _CountingPainter(clock.frame, () => paints += 1),
    ),
  );
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(Listenable repaint, this.onPaint) : super(repaint: repaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint();

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

final GlobalKey<_ClockHostState> _hostKey = GlobalKey<_ClockHostState>();

_ClockHostState _host(WidgetTester tester) => _hostKey.currentState!;

Widget _app({
  ValueListenable<bool>? reduceMotion,
  ValueListenable<bool>? constrained,
  bool disableAnimations = false,
  Widget? home,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: MotionPolicyScope(
      reduceMotion: reduceMotion,
      constrained: constrained,
      child: child!,
    ),
  ),
  home:
      home ??
      Scaffold(
        body: Center(child: _ClockHost(key: _hostKey)),
      ),
);

/// Pumps one second of 120 Hz frames.
Future<void> _pumpSecond(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(microseconds: 8333));
  }
}

void main() {
  testWidgets('the clock never asks for more than 24 frames a second', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final host = _host(tester);
    expect(host.clock.isRunning, isTrue);
    final before = host.paints;
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value - frames, inInclusiveRange(20, 24));
    expect(host.paints - before, inInclusiveRange(20, 24));
    expect(host.clock.elapsed, greaterThan(const Duration(milliseconds: 800)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a hidden or paused app pauses the clock and resumes it', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final host = _host(tester);
    await _pumpSecond(tester);
    expect(host.clock.isRunning, isTrue);

    // A desktop window that merely lost focus is inactive yet fully visible:
    // its work keeps moving.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(host.clock.isRunning, isTrue);
    expect(host.clock.pauseReasons['lifecycle'], isFalse);
    final inactiveFrames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(
      host.clock.frame.value - inactiveFrames,
      inInclusiveRange(20, 24),
      reason: 'still animating while inactive',
    );

    for (final state in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(host.clock.isRunning, isFalse, reason: '$state');
      expect(host.clock.pauseReasons['lifecycle'], isTrue);
      final frames = host.clock.frame.value;
      final elapsed = host.clock.elapsed;
      await _pumpSecond(tester);
      expect(host.clock.frame.value, frames, reason: 'still while $state');
      expect(host.clock.elapsed, elapsed);
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.clock.isRunning, isTrue);
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value - frames, inInclusiveRange(20, 24));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a route pushed above the clock pauses it until it is popped', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final host = _host(tester);
    await _pumpSecond(tester);
    final context = tester.element(find.byKey(_hostKey));
    final dialog = showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(title: Text('Above')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(host.clock.isRunning, isFalse);
    expect(host.clock.pauseReasons['route'], isTrue);
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, frames);

    Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(host.clock.isRunning, isTrue);
    final resumed = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value - resumed, inInclusiveRange(20, 24));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduce motion holds the clock still, from either source', (
    tester,
  ) async {
    final reduce = ValueNotifier<bool>(false);
    addTearDown(reduce.dispose);
    await tester.pumpWidget(_app(reduceMotion: reduce));
    final host = _host(tester);
    expect(host.clock.isStatic, isFalse);
    await _pumpSecond(tester);

    reduce.value = true;
    await tester.pump();
    expect(host.clock.isStatic, isTrue);
    expect(host.clock.isRunning, isFalse);
    // One static picture is drawn when motion stops, then nothing.
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, frames);

    reduce.value = false;
    await tester.pump();
    expect(host.clock.isStatic, isFalse);
    final live = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value - live, inInclusiveRange(20, 24));

    // The ambient media query is honoured without a scope value.
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump();
    expect(host.clock.isStatic, isTrue);
    expect(host.clock.policy.reduceMotion, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an essential clock ignores reduce motion but not the brake', (
    tester,
  ) async {
    final reduce = ValueNotifier<bool>(false);
    final constrained = ValueNotifier<bool>(false);
    addTearDown(reduce.dispose);
    addTearDown(constrained.dispose);
    final clock = MotionClock(essential: true);
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      _app(
        reduceMotion: reduce,
        constrained: constrained,
        home: Builder(
          builder: (context) {
            clock.attach(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(clock.isRunning, isTrue);
    reduce.value = true;
    await tester.pump();
    expect(clock.isStatic, isFalse);
    expect(clock.isRunning, isTrue);
    expect(clock.policy.reduceMotion, isTrue);
    constrained.value = true;
    await tester.pump();
    expect(clock.isStatic, isTrue);
    expect(clock.isRunning, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the renderer brake holds the clock still for good', (
    tester,
  ) async {
    final constrained = ValueNotifier<bool>(false);
    addTearDown(constrained.dispose);
    await tester.pumpWidget(_app(constrained: constrained));
    final host = _host(tester);
    await _pumpSecond(tester);
    expect(host.clock.isRunning, isTrue);

    constrained.value = true;
    await tester.pump();
    expect(host.clock.isStatic, isTrue);
    expect(host.clock.policy.constrained, isTrue);
    expect(host.clock.pauseReasons['policy'], isTrue);
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, frames);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a surface scrolled out of its viewport pauses, and resumes', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 2000),
                _ClockHost(key: _hostKey),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    final host = _host(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(host.clock.isRunning, isFalse, reason: 'starts below the fold');
    expect(host.clock.pauseReasons['offScreen'], isTrue);
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, frames);

    scroll.jumpTo(1900);
    await tester.pump();
    expect(host.clock.isRunning, isTrue, reason: 'scrolled into view');
    final visible = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value - visible, inInclusiveRange(20, 24));

    scroll.jumpTo(0);
    await tester.pump();
    expect(host.clock.isRunning, isFalse, reason: 'scrolled away again');
    final away = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, away);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a suspended clock stays still until it is attached again', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final host = _host(tester);
    await _pumpSecond(tester);
    host.clock.suspend();
    expect(host.clock.isRunning, isFalse);
    expect(host.clock.pauseReasons['suspended'], isTrue);
    final frames = host.clock.frame.value;
    await _pumpSecond(tester);
    expect(host.clock.frame.value, frames);
    host.clock.attach(tester.element(find.byKey(_hostKey)));
    expect(host.clock.isRunning, isTrue);
    await _pumpSecond(tester);
    expect(host.clock.frame.value - frames, inInclusiveRange(20, 24));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MotionPolicy.of reads the scope and the media query', (
    tester,
  ) async {
    final reduce = ValueNotifier<bool>(true);
    final constrained = ValueNotifier<bool>(true);
    addTearDown(reduce.dispose);
    addTearDown(constrained.dispose);
    late MotionPolicy policy;
    await tester.pumpWidget(
      MotionPolicyScope(
        reduceMotion: reduce,
        constrained: constrained,
        child: Builder(
          builder: (context) {
            policy = MotionPolicy.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(policy, const MotionPolicy(reduceMotion: true, constrained: true));
    expect(policy.animates, isFalse);
    reduce.value = false;
    constrained.value = false;
    await tester.pump();
    expect(policy, const MotionPolicy());
    expect(policy.animates, isTrue);
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          policy = MotionPolicy.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(policy, const MotionPolicy(), reason: 'no scope, no media query');
  });
}
