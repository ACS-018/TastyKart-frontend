import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/color_constants.dart';
import '../models/customer_account.dart';
import '../models/favorite_restaurant.dart';
import '../services/firestore_service.dart';
import '../services/address_service.dart';
import '../services/auth_service.dart';
import '../services/customer_account_service.dart';
import '../services/favorites_service.dart';
import '../services/fcm_service.dart';
import '../services/wallet_service.dart';
import '../state/cart_controller.dart';
import '../state/favorites_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/app_navigation.dart';
import 'Home/home_screen.dart';
import 'auth/login_screen.dart';

/// Shows [LoginScreen] when signed out, [HomeScreen] when signed in and active.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.favoritesController});

  final FavoritesController favoritesController;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Used to detect logout so we can clear pushed routes (checkout, menu, etc.).
  User? _previousUser;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.primary,
            body: SafeArea(
              top: false,
              child: ColoredBox(
                color: AppColors.primary,
                child: SafeArea(
                  child: ColoredBox(
                    color: AppColors.background,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          final justLoggedOut = _previousUser != null;
          _previousUser = null;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.favoritesController.clear();
            CartScope.maybeOf(context)?.clear();
            if (justLoggedOut) {
              AppNavigation.goToAuthRoot();
            }
          });
          return const LoginScreen();
        }

        _previousUser = user;
        // Refresh FCM token on every sign-in so Firestore always has a fresh token.
        UserFCMService.initialize();
        return _SignedInShell(
          user: user,
          favoritesController: widget.favoritesController,
        );
      },
    );
  }
}

class _SignedInShell extends StatefulWidget {
  const _SignedInShell({required this.user, required this.favoritesController});

  final User user;
  final FavoritesController favoritesController;

  @override
  State<_SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<_SignedInShell>
    with WidgetsBindingObserver {
  StreamSubscription<List<DeliveryAddress>>? _addressSub;
  StreamSubscription<List<FavoriteRestaurant>>? _favoritesSub;
  StreamSubscription<CustomerAccount?>? _statusSub;
  StreamSubscription<dynamic>? _subscriptionSub;
  StreamSubscription<int>? _walletSub;

  bool _checkingAccess = true;
  bool _handlingBlock = false;
  String? _accessError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindUser();
      _verifyAccess(initial: true);
    });
  }

  @override
  void didUpdateWidget(covariant _SignedInShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _bindUser();
      _verifyAccess(initial: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyAccess();
    }
  }

  void _bindUser() {
    final cart = CartScope.maybeOf(context);

    cart?.setCustomer(
      id: widget.user.uid,
      name: widget.user.displayName?.trim().isNotEmpty == true
          ? widget.user.displayName!
          : (widget.user.email ?? 'Customer'),
      phone: widget.user.phoneNumber ?? '+91 00000 00000',
    );

    // Eagerly seed the cart with the default address via a one-shot fetch
    // so it's available immediately — before the real-time stream fires.
    // This prevents the "add delivery address" prompt from flashing on
    // every app launch or after an order is completed.
    if (cart != null && !cart.hasDeliveryAddress) {
      AddressService.watchForUser(widget.user.uid).first
          .then((list) {
            if (!mounted) return;
            cart.syncAddressesFromFirestore(list);
          })
          .catchError((_) {});
    }

    _addressSub?.cancel();
    _addressSub = AddressService.watchForUser(
      widget.user.uid,
    ).listen((list) => cart?.syncAddressesFromFirestore(list));

    _favoritesSub?.cancel();
    _favoritesSub = FavoritesService.watchForUser(
      widget.user.uid,
    ).listen(widget.favoritesController.syncFromFirestore, onError: (_, __) {});

    _statusSub?.cancel();
    _statusSub = CustomerAccountService.watchForUser(widget.user).listen((
      account,
    ) {
      if (CustomerAccountService.isBlockedAccount(account)) {
        _forceLogoutForBlock(account!);
      }
    }, onError: (_, __) {});

    // Live subscription status → update cart's free-delivery flag.
    _subscriptionSub?.cancel();
    _subscriptionSub = FirestoreService.watchCustomerDoc(widget.user.uid)
        .listen((doc) {
          if (!doc.exists || !mounted) return;
          final account = CustomerAccount.fromMap(
            widget.user.uid,
            doc.data() as Map<String, dynamic>? ?? {},
          );
          CartScope.maybeOf(
            context,
          )?.setSubscriptionActive(account.hasActiveSubscription);
        }, onError: (_, __) {});

    // Live wallet balance → keep cart in sync.
    _walletSub?.cancel();
    _walletSub = WalletService.watchBalance(widget.user.uid).listen((balance) {
      if (!mounted) return;
      CartScope.maybeOf(context)?.setWalletBalance(balance);
    }, onError: (_, __) {});
  }

  Future<void> _verifyAccess({bool initial = false}) async {
    if (_handlingBlock) return;
    if (initial && mounted) {
      setState(() {
        _checkingAccess = true;
        _accessError = null;
      });
    }

    try {
      await AuthService.enforceCustomerAccess(widget.user);
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _accessError = null;
      });
    } on CustomerBlockedException catch (e) {
      await _forceLogoutForBlock(e.account);
    } catch (e) {
      if (!mounted) return;
      // Network blips: keep session, show retry on initial gate only.
      setState(() {
        _checkingAccess = false;
        _accessError = initial
            ? 'Could not verify account status. Pull to retry.'
            : null;
      });
    }
  }

  Future<void> _forceLogoutForBlock(CustomerAccount account) async {
    if (_handlingBlock) return;
    _handlingBlock = true;

    final message = account.blockMessage;
    if (mounted) {
      AppFeedback.showError(context, message);
      CartScope.maybeOf(context)?.clear();
    }
    widget.favoritesController.clear();

    try {
      await AuthService.logout();
    } catch (_) {}

    _handlingBlock = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addressSub?.cancel();
    _favoritesSub?.cancel();
    _statusSub?.cancel();
    _subscriptionSub?.cancel();
    _walletSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: AppColors.primary,
            child: SafeArea(
              child: ColoredBox(
                color: AppColors.background,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      );
    }

    if (_accessError != null) {
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          top: false,
          child: ColoredBox(
            color: AppColors.primary,
            child: SafeArea(
              child: ColoredBox(
                color: AppColors.background,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_accessError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => _verifyAccess(initial: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}
