import 'package:flutter/material.dart';

/// Breakpoints used across the app.
/// Adjust these values to match your design system.
class AppBreakpoints {
  AppBreakpoints._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;
  // > 1024 is considered desktop
}

/// Responsive helper that exposes screen dimensions and
/// convenience booleans based on [MediaQuery].
///
/// Usage:
///   final r = Responsive.of(context);
///   if (r.isMobile) { ... }
///   double padding = r.responsive(mobile: 16, tablet: 24, desktop: 32);
class Responsive {
  Responsive._({
    required this.screenWidth,
    required this.screenHeight,
    required this.devicePixelRatio,
    required this.textScaleFactor,
    required this.orientation,
  });

  /// Creates a [Responsive] instance from the given [BuildContext].
  factory Responsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Responsive._(
      screenWidth: mq.size.width,
      screenHeight: mq.size.height,
      devicePixelRatio: mq.devicePixelRatio,
      textScaleFactor: mq.textScaler.scale(1),
      orientation: mq.orientation,
    );
  }

  final double screenWidth;
  final double screenHeight;
  final double devicePixelRatio;
  final double textScaleFactor;
  final Orientation orientation;

  // ── Breakpoint booleans ──────────────────────────────────────────────────

  bool get isMobile => screenWidth < AppBreakpoints.mobileMax;
  bool get isTablet =>
      screenWidth >= AppBreakpoints.mobileMax &&
      screenWidth <= AppBreakpoints.tabletMax;
  bool get isDesktop => screenWidth > AppBreakpoints.tabletMax;

  bool get isPortrait => orientation == Orientation.portrait;
  bool get isLandscape => orientation == Orientation.landscape;

  // ── Percentage helpers ───────────────────────────────────────────────────

  /// Returns [percent]% of screen width (0–100).
  double wp(double percent) => screenWidth * percent / 100;

  /// Returns [percent]% of screen height (0–100).
  double hp(double percent) => screenHeight * percent / 100;

  // ── Responsive value picker ──────────────────────────────────────────────

  /// Returns the value matching the current breakpoint.
  /// [tablet] and [desktop] fall back to [mobile] when not provided.
  T responsive<T>({required T mobile, T? tablet, T? desktop}) {
    if (isDesktop) return desktop ?? tablet ?? mobile;
    if (isTablet) return tablet ?? mobile;
    return mobile;
  }

  @override
  String toString() =>
      'Responsive(${screenWidth.toStringAsFixed(0)}×${screenHeight.toStringAsFixed(0)}, '
      '${isMobile
          ? "mobile"
          : isTablet
          ? "tablet"
          : "desktop"}, '
      '${isPortrait ? "portrait" : "landscape"})';
}

/// Convenience widget that rebuilds its subtree with a [Responsive] instance
/// whenever the screen size changes.
///
/// Usage:
///   ResponsiveBuilder(
///     builder: (context, r) => Text('Width: ${r.screenWidth}'),
///   )
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Responsive r) builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, Responsive.of(context));
  }
}

/// Renders a different widget per breakpoint.
///
/// Usage:
///   BreakpointWidget(
///     mobile: MobileLayout(),
///     tablet: TabletLayout(),      // optional — falls back to mobile
///     desktop: DesktopLayout(),    // optional — falls back to tablet/mobile
///   )
class BreakpointWidget extends StatelessWidget {
  const BreakpointWidget({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    if (r.isDesktop) return desktop ?? tablet ?? mobile;
    if (r.isTablet) return tablet ?? mobile;
    return mobile;
  }
}
