import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Clamps the parametric value to [0,1] before passing to [curve]. Prevents
/// "parametric value outside of [0, 1] range" when a controller occasionally exceeds 1.
class ClampedCurve extends Curve {
  const ClampedCurve(this.curve);
  final Curve curve;

  @override
  double transformInternal(double t) {
    return curve.transform(t.clamp(0.0, 1.0));
  }
}

/// Shared animation durations and curves for the app.
/// Stronger, more visible animations like the website (animate__fadeInDown, zoomIn, etc.).
class AppAnimations {
  AppAnimations._();

  static const Duration snappy = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 320);
  static const Duration medium = Duration(milliseconds: 400);
  static const Duration slow = Duration(milliseconds: 550);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  /// More punchy (website-style): slight overshoot then settle.
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve bounce = Curves.elasticOut;
  /// Snappy pop for list items / modals (like animate__zoomIn).
  static const Curve pop = Curves.easeOutBack;
}

/// Wraps [child] in a fade + slide animation that runs once when first built.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppAnimations.normal,
    this.curve = AppAnimations.emphasized,
    this.offset = const Offset(0, 24),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // Use easeOut for opacity so value stays in [0,1] (emphasized/easeOutBack can overshoot)
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _offset = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: ClampedCurve(widget.curve)));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: _offset.value,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Full-screen heart burst overlay for double-tap like (e.g. on feed media).
class HeartBurstOverlay extends StatefulWidget {
  const HeartBurstOverlay({
    super.key,
    this.size = 100,
    this.color = Colors.red,
    this.onComplete,
  });

  final double size;
  final Color color;
  final VoidCallback? onComplete;

  @override
  State<HeartBurstOverlay> createState() => _HeartBurstOverlayState();
}

class _HeartBurstOverlayState extends State<HeartBurstOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scale = Tween<double>(begin: 0.2, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: const ClampedCurve(Curves.easeOutBack)),
    );
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1, curve: Curves.easeOut),
      ),
    );
    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Opacity(
          opacity: _opacity.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _scale.value,
            child: Icon(
              Icons.favorite,
              size: widget.size,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared page/content transition: fade + slide (used in main.dart and home_shell.dart).
/// Reduces duplication and keeps animation behavior consistent.
Widget bondhuPageTransitionBuilder(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  final slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: AppAnimations.emphasized));
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(position: slide, child: child),
  );
}

/// Horizontal slide variant for tab content (e.g. desktop sidebar).
Widget bondhuTabTransitionBuilder(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  final slide = Tween<Offset>(
    begin: const Offset(0.06, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: AppAnimations.emphasized));
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(position: slide, child: child),
  );
}

/// Minimum touch target size (Material: 48dp). Improves tap reliability on phone.
const double kMinTouchTargetSize = 48.0;

/// Scale-down feedback when pressed (wrap buttons/icons). More noticeable like website.
/// Uses opaque hit test and minimum touch target so taps register reliably in scrollables.
class ScaleTap extends StatefulWidget {
  const ScaleTap({
    super.key,
    required this.onTap,
    required this.child,
    this.scale = 0.88,
    /// If true, ensures at least [kMinTouchTargetSize] so taps are easy on phone. Default true.
    this.applyMinTouchTarget = true,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double scale;
  final bool applyMinTouchTarget;

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.snappy,
    );
    _scale = Tween<double>(begin: 1, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: ClampedCurve(AppAnimations.emphasized)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) => _controller.forward();
  void _onTapUp(TapUpDetails details) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  void _onTap() {
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: widget.child,
    );
    if (widget.applyMinTouchTarget) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinTouchTargetSize,
          minHeight: kMinTouchTargetSize,
        ),
        child: Center(child: content),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      child: content,
    );
  }
}
