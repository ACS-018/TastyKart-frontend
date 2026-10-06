import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'constants/app_constants.dart';
import 'constants/color_constants.dart';
import 'models/admin_models.dart';
import 'screens/auth_gate.dart';
import 'services/fcm_service.dart';
import 'services/firestore_service.dart';
import 'services/force_update_service.dart';
import 'state/cart_controller.dart';
import 'state/diet_filter_controller.dart';
import 'state/favorites_controller.dart';
import 'state/home_filter_controller.dart';
import 'utils/app_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Initialise FCM — requests permission, stores token, sets up listeners.
  await UserFCMService.initialize();
  runApp(const TastyKartApp());
}

class TastyKartApp extends StatefulWidget {
  const TastyKartApp({super.key});

  @override
  State<TastyKartApp> createState() => _TastyKartAppState();
}

class _TastyKartAppState extends State<TastyKartApp> {
  final CartController _cart = CartController();
  final FavoritesController _favorites = FavoritesController();
  final DietFilterController _dietFilter = DietFilterController();
  final HomeFilterController _homeFilter = HomeFilterController();
  StreamSubscription? _settingsSub;
  StreamSubscription? _surgeSub;

  @override
  void initState() {
    super.initState();
    // Check for force-update after the first frame so the navigator is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ForceUpdateService.start();
    });
    _settingsSub = FirestoreService.adminSettings().listen((doc) {
      final charges = PlatformCharges.fromSettingsDoc(doc);
      debugPrint(
        '📦 PlatformCharges loaded: '
        'perKmRate=${charges.perKmRate}, '
        'base=${charges.baseDeliveryFee}, '
        'max=${charges.maxDeliveryFee}, '
        'surge=${charges.surgeMultiplier}',
      );
      _cart.applyCharges(charges);
    });
    _surgeSub = FirestoreService.approvedSurgeRequests().listen((snap) {
      _cart.setActiveSurges(snap.docs.map(_citySurgeFromDoc).toList());
    });
  }

  CitySurge _citySurgeFromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CitySurge(
      city: (data['city'] as String? ?? '').trim(),
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      startsAt: _readSurgeTime(data['startsAt']),
      endsAt: _readSurgeTime(data['endsAt']),
    );
  }

  DateTime? _readSurgeTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _surgeSub?.cancel();
    _cart.dispose();
    _favorites.dispose();
    _dietFilter.dispose();
    _homeFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CartScope(
      controller: _cart,
      child: DietFilterScope(
        controller: _dietFilter,
        child: FavoritesScope(
          controller: _favorites,
          child: HomeFilterScope(
            controller: _homeFilter,
            child: MaterialApp(
              title: AppConstants.appName,
              navigatorKey: AppNavigation.rootNavigatorKey,
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: AppColors.primary,
                  surface: AppColors.background,
                ),
                scaffoldBackgroundColor: AppColors.background,
                useMaterial3: true,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              home: AuthGate(favoritesController: _favorites),
            ),
          ),
        ),
      ),
    );
  }
}
