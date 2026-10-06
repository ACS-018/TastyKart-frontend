import 'package:flutter/material.dart';

/// Smooth navigation helpers — same screens, nicer transitions.
class AppNavigation {
  AppNavigation._();

  /// Root navigator for MaterialApp — used to return to AuthGate after logout.
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  /// Drop overlay routes so [AuthGate] (login / home) is visible.
  static void goToAuthRoot() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  static Future<T?> push<T>(
    BuildContext context,
    Widget page, {
    bool fade = false,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) {
          if (fade) {
            return FadeTransition(opacity: animation, child: child);
          }
          const begin = Offset(0.03, 0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
      ),
    );
  }
}
