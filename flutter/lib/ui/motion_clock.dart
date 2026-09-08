import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion_policy.dart';

/// Drives a continuously animating decoration from a timer instead of a
/// vsync ticker, and holds it still whenever nobody can see it.
///
/// A scheduled [Ticker] forces a full engine frame every vsync — on a 120 Hz
/// desktop display that is 120 pictures a second even when the painter
/// itself skips most of them. A [Timer] at [frameInterval] asks for at most
/// 24 frames a second, and only while all of these hold:
///
/// * the application is visible: resumed or inactive (an unfocused desktop
///   window still shows its work), not hidden, paused, or detached;
/// * the route the widget sits on is the current one — a detail modal open
///   above the studio stops the card underneath it;
/// * the widget is inside its enclosing scroll viewport;
/// * the [MotionPolicy] allows motion — neither reduce-motion nor the
///   renderer's memory brake is on.
///
/// When the policy forbids motion the owner draws one static frame; the
/// other three reasons simply pause the clock and resume it later from the
/// same phase. An [essential] clock — a progress indicator, which conveys
/// state rather than decoration — ignores the person's reduce-motion
/// preference and stops only for the renderer's memory brake.
///
/// Every running clock with the same [frameInterval] ticks from one shared
/// timer, so a page with several animating surfaces still asks the engine for
/// one frame per tick rather than one per surface.
///
/// Owners call [attach] from `didChangeDependencies` (it reads the policy,
/// the route, and the scrollable through the context) and [dispose] from
/// their own `dispose`. [frame] is the repaint listenable to hand a
/// [CustomPainter]; [elapsed] is the animation time it should draw.
class MotionClock with WidgetsBindingObserver {
  MotionClock({
    this.frameInterval = defaultFrameInterval,
    this.onTick,
    this.essential = false,
  });

  /// Whether this motion conveys state (a progress indicator) rather than
  /// decoration, and so keeps moving under reduce motion.
  final bool essential;

  /// Whether [state] leaves the window on screen: a desktop window that lost
  /// focus is `inactive` yet fully visible, so its work keeps moving.
  static bool lifecycleAnimates(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  /// 24 frames a second: the cadence of film, and plenty for snow, a glow
  /// drift, or a slowly filling bar.
  static const Duration defaultFrameInterval = Duration(microseconds: 41667);

  /// How often the clock re-checks the viewport while it is paused only for
  /// being scrolled out of sight. Scrolling itself triggers a check sooner.
  static const Duration offScreenPoll = Duration(milliseconds: 250);

  final Duration frameInterval;

  /// Called on every animation frame, before [frame] is bumped, with the
  /// animation time. Owners that step a simulation do it here.
  final void Function(Duration elapsed)? onTick;

  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Timer? _timer;
  bool _running = false;
  Duration _elapsed = Duration.zero;
  bool _attached = false;
  bool _observing = false;
  bool _disposed = false;

  BuildContext? _context;
  ScrollPosition? _position;
  MotionPolicy _policy = const MotionPolicy();
  bool _routeCurrent = true;
  bool _lifecycleResumed = true;
  bool _onScreen = true;
  bool _suspended = false;

  /// Bumped once per animation frame; the painter's `repaint` listenable.
  ValueListenable<int> get frame => _frame;

  /// The animation time at the latest frame. Advances only while running,
  /// so a pause and resume continue from the same phase.
  Duration get elapsed => _elapsed;

  /// The policy read at the last [attach].
  MotionPolicy get policy => _policy;

  /// True when the policy allows motion and every pause reason is clear.
  bool get isRunning => _running && _animating;

  /// True when the policy forbids motion and the owner should draw its
  /// single static frame.
  bool get isStatic => !_policyAllows;

  bool get _policyAllows => essential ? !_policy.constrained : _policy.animates;

  /// Why the clock is not running, for tests and diagnostics.
  @visibleForTesting
  Map<String, bool> get pauseReasons => <String, bool>{
    'policy': !_policyAllows,
    'lifecycle': !_lifecycleResumed,
    'route': !_routeCurrent,
    'offScreen': !_onScreen,
    'suspended': _suspended,
  };

  bool get _animating =>
      _policyAllows &&
      _lifecycleResumed &&
      _routeCurrent &&
      _onScreen &&
      !_suspended;

  /// Holds the clock until the next [attach]: for an owner that has nothing
  /// to animate right now, such as a bar that just received a real value.
  void suspend() {
    if (_disposed || _suspended) return;
    _suspended = true;
    _sync();
  }

  /// Reads the policy, route, lifecycle, and scrollable above [context] and
  /// (re)starts or pauses the clock accordingly. Call from
  /// `didChangeDependencies`.
  void attach(BuildContext context) {
    assert(!_disposed, 'MotionClock used after dispose');
    _context = context;
    _attached = true;
    _suspended = false;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    final policy = MotionPolicy.of(context);
    final wasStatic = isStatic;
    _policy = policy;
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleResumed = lifecycleAnimates(lifecycle);
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_handleScroll);
      _position = position;
      _position?.addListener(_handleScroll);
    }
    // The render object may not have been laid out yet; assume it is in view
    // and let the first tick correct that.
    _onScreen = _checkOnScreen() ?? true;
    _sync();
    // A policy flip needs one more picture: the static frame when motion
    // stops, or the first live frame when it is allowed again.
    if (wasStatic != isStatic) _frame.value += 1;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = lifecycleAnimates(state);
    if (resumed == _lifecycleResumed) return;
    _lifecycleResumed = resumed;
    _sync();
  }

  void _handleScroll() {
    if (_disposed || !_attached) return;
    final visible = _checkOnScreen();
    if (visible == null || visible == _onScreen) return;
    _onScreen = visible;
    _sync();
  }

  /// Whether the owner's render object overlaps every viewport it sits in,
  /// or null when that cannot be known yet.
  ///
  /// Measured in each viewport's own coordinates — the paint transform
  /// already carries the scroll offset — so a card in a horizontal strip
  /// inside the page's vertical scroll is judged against both.
  bool? _checkOnScreen() {
    final context = _context;
    if (context == null || !context.mounted) return null;
    final target = context.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    try {
      RenderObject? probe = target;
      while (true) {
        final viewport = RenderAbstractViewport.maybeOf(probe);
        if (viewport is! RenderBox) return true;
        final box = viewport as RenderBox;
        if (!box.hasSize) return null;
        final bounds = MatrixUtils.transformRect(
          target.getTransformTo(box),
          target.paintBounds,
        );
        if (!bounds.overlaps(Offset.zero & box.size)) return false;
        probe = box.parent;
      }
    } on Object {
      // A viewport mid-layout can refuse the question; keep the last answer.
      return null;
    }
  }

  void _sync() {
    if (_disposed) return;
    if (_animating) {
      _stopPolling();
      if (!_running) {
        _running = true;
        _MotionPacer.of(frameInterval).add(this);
      }
      return;
    }
    if (_running) {
      _running = false;
      _MotionPacer.of(frameInterval).remove(this);
    }
    _stopPolling();
    if (_policyAllows &&
        _lifecycleResumed &&
        _routeCurrent &&
        !_onScreen &&
        !_suspended) {
      // Only the viewport holds it back: look again now and then, because
      // an ancestor can move the card into view without a scroll event.
      _timer = Timer.periodic(offScreenPoll, (_) => _handleScroll());
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// One shared tick from the pacer.
  void _tick() {
    if (_disposed || !_running) return;
    // Re-check the viewport on the animation cadence: cheap, and it catches a
    // card that an ancestor's relayout carried out of view.
    final visible = _checkOnScreen();
    if (visible == false) {
      _onScreen = false;
      _sync();
      return;
    }
    _elapsed += frameInterval;
    onTick?.call(_elapsed);
    _frame.value += 1;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_running) {
      _running = false;
      _MotionPacer.of(frameInterval).remove(this);
    }
    _stopPolling();
    _position?.removeListener(_handleScroll);
    _position = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _context = null;
    _frame.dispose();
  }
}

/// The one timer behind every running [MotionClock] of a given interval. It
/// exists only while at least one clock runs, so an idle page holds no timer.
class _MotionPacer {
  _MotionPacer._(this.interval);

  static final Map<Duration, _MotionPacer> _pacers = <Duration, _MotionPacer>{};

  static _MotionPacer of(Duration interval) =>
      _pacers[interval] ??= _MotionPacer._(interval);

  final Duration interval;
  final Set<MotionClock> _clocks = <MotionClock>{};
  Timer? _timer;

  void add(MotionClock clock) {
    _clocks.add(clock);
    _timer ??= Timer.periodic(interval, _tick);
  }

  void remove(MotionClock clock) {
    _clocks.remove(clock);
    if (_clocks.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _pacers.remove(interval);
    }
  }

  void _tick(Timer _) {
    // A clock may pause or dispose itself while ticking; iterate a copy.
    for (final clock in _clocks.toList(growable: false)) {
      clock._tick();
    }
  }
}
