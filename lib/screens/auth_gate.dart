import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/delivery_address.dart';
import '../services/address_service.dart';
import '../services/auth_service.dart';
import '../state/cart_controller.dart';
import 'Home/home_screen.dart';
import 'auth/login_screen.dart';

/// Shows [LoginScreen] when signed out, [HomeScreen] when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return _SignedInShell(user: user);
      },
    );
  }
}

class _SignedInShell extends StatefulWidget {
  const _SignedInShell({required this.user});

  final User user;

  @override
  State<_SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<_SignedInShell> {
  StreamSubscription<List<DeliveryAddress>>? _addressSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindUser());
  }

  @override
  void didUpdateWidget(covariant _SignedInShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _bindUser();
    }
  }

  void _bindUser() {
    final cart = CartScope.maybeOf(context);
    if (cart == null) return;

    cart.setCustomer(
      id: widget.user.uid,
      name: widget.user.displayName?.trim().isNotEmpty == true
          ? widget.user.displayName!
          : (widget.user.email ?? 'Customer'),
      phone: widget.user.phoneNumber ?? '+91 00000 00000',
    );

    _addressSub?.cancel();
    _addressSub = AddressService.watchForUser(widget.user.uid).listen(
      cart.syncAddressesFromFirestore,
    );
  }

  @override
  void dispose() {
    _addressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
