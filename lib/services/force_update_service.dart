import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/color_constants.dart';
import '../utils/app_navigation.dart';
import 'firestore_paths.dart';

/// Force-update guard for the TastyKart customer app.
///
/// How it works:
///   1. On startup it subscribes to `settings/admin` with a **live stream**
///      (onSnapshot). Every time the admin changes `appVersions.userApp.minBuild`
///      in the admin panel, ALL running app instances receive the update in
///      real-time and show the update screen immediately.
///   2. The update screen is a full-screen route pushed with `pushAndRemoveUntil`
///      so the back-stack is empty — the user has no way to navigate back.
///   3. `onPopInvokedWithResult` sends the app to background if the system
///      tries to pop the route, so the user must update before returning.
///   4. When the app resumes from background the stream re-evaluates — if the
///      admin lowered the requirement the normal app resumes automatically.
///
/// Usage — call [ForceUpdateService.start] once from the root [initState].
class ForceUpdateService with WidgetsBindingObserver {
  ForceUpdateService._();

  static final _instance = ForceUpdateService._();

  static bool _started = false;
  static StreamSubscription<DocumentSnapshot>? _sub;

  // Last evaluated state — used to avoid pushing the screen twice.
  static bool _updateScreenShown = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call exactly once from the root widget's [initState].
  static Future<void> start() async {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(_instance);

    // Get the installed build number once — it never changes at runtime.
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final currentVersion = '${info.version}+${info.buildNumber}';

    debugPrint('[ForceUpdate] installed build=$currentBuild ($currentVersion)');

    // Subscribe to the settings doc — fires immediately with the current
    // value, then again whenever the admin saves a change.
    _sub = FirebaseFirestore.instance
        .collection(FirestorePaths.settings)
        .doc(FirestorePaths.settingsAdminDoc)
        .snapshots()
        .listen(
          (snap) => _instance._onSettingsSnapshot(
            snap,
            currentBuild: currentBuild,
            currentVersion: currentVersion,
          ),
          onError: (e) => debugPrint('[ForceUpdate] stream error: $e'),
        );
  }

  // ── WidgetsBindingObserver ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from Play Store the stream will have already received
    // any Firestore change. We only need to re-show the screen if the update
    // is still required but the screen was somehow dismissed.
    if (state == AppLifecycleState.resumed && _updateScreenShown) {
      final ctx = AppNavigation.rootNavigatorKey.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        final route = ModalRoute.of(ctx);
        final onUpdateScreen = route?.settings.name == '/force-update';
        if (!onUpdateScreen) {
          // Screen was dismissed — push it again.
          debugPrint('[ForceUpdate] resumed without updating — re-showing');
          _instance._pushUpdateScreenIfNeeded(ctx, currentVersion: '');
        }
      }
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onSettingsSnapshot(
    DocumentSnapshot snap, {
    required int currentBuild,
    required String currentVersion,
  }) {
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>? ?? {};

    final appVersions = data['appVersions'];
    if (appVersions is! Map) return;

    final userApp = appVersions['userApp'];
    if (userApp is! Map) return;

    final minBuild = (userApp['minBuild'] as num?)?.toInt() ?? 0;
    final minVersionName = (userApp['minVersionName'] as String?)?.trim() ?? '';
    final playStoreUrl = (userApp['playStoreUrl'] as String?)?.trim() ?? '';

    debugPrint(
      '[ForceUpdate] snapshot → minBuild=$minBuild currentBuild=$currentBuild',
    );

    if (minBuild <= 0 || currentBuild >= minBuild) {
      _updateScreenShown = false;
      debugPrint('[ForceUpdate] no update required');
      return;
    }

    if (_updateScreenShown) return;

    // Defer navigation to the next frame so it never fires during a build.
    // The first Firestore snapshot arrives immediately after subscription and
    // may land inside a postFrameCallback / initState context — pushing a
    // route there causes "dirty widget in wrong build scope".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = AppNavigation.rootNavigatorKey.currentContext;
      if (ctx == null) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          final ctx2 = AppNavigation.rootNavigatorKey.currentContext;
          if (ctx2 != null) {
            _pushUpdateScreenIfNeeded(
              ctx2,
              currentVersion: currentVersion,
              minVersionName: minVersionName,
              playStoreUrl: playStoreUrl,
            );
          }
        });
        return;
      }
      _pushUpdateScreenIfNeeded(
        ctx,
        currentVersion: currentVersion,
        minVersionName: minVersionName,
        playStoreUrl: playStoreUrl,
      );
    });
  }

  void _pushUpdateScreenIfNeeded(
    BuildContext context, {
    required String currentVersion,
    String minVersionName = '',
    String playStoreUrl = '',
  }) {
    _updateScreenShown = true;
    // ignore: use_build_context_synchronously
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: '/force-update'),
        pageBuilder: (_, __, ___) => _ForceUpdateScreen(
          currentVersion: currentVersion,
          requiredVersionName: minVersionName,
          playStoreUrl: playStoreUrl,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
      (_) => false, // remove entire back-stack
    );
  }
}

// ── Full-screen update screen ─────────────────────────────────────────────────

class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen({
    required this.currentVersion,
    required this.requiredVersionName,
    required this.playStoreUrl,
  });

  final String currentVersion;
  final String requiredVersionName;
  final String playStoreUrl;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Send app to background — user cannot bypass the update screen.
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 52,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Update Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  requiredVersionName.isNotEmpty
                      ? 'Version $requiredVersionName is required to continue using TastyKart. Please update now.'
                      : 'A newer version of TastyKart is required. Please update to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF6B7280),
                    height: 1.6,
                  ),
                ),
                if (currentVersion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your version: $currentVersion',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: playStoreUrl.isEmpty
                        ? null
                        : () async {
                            final uri = Uri.tryParse(playStoreUrl);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text(
                      'Update on Play Store',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
