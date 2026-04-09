import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Global scroll behavior: clamping physics on mobile to avoid "shaking"
/// when reaching the top/bottom of scroll views. This keeps scrolling
/// stable on phones while still allowing platform defaults on web/desktop.
class BondhuScrollBehavior extends MaterialScrollBehavior {
  const BondhuScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (kIsWeb) return child;
    return super.buildScrollbar(context, child, details);
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // On web/desktop keep default MaterialScrollBehavior (bouncing on macOS/iOS).
    switch (getPlatform(context)) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        // Clamping physics removes the bounce "shake" at the edges.
        return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      default:
        return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
  }
}
