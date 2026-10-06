import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/customer_account.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';
import '../../services/firestore_service.dart';
import '../../services/wallet_service.dart';
import '../../state/cart_controller.dart';
import '../../state/diet_filter_controller.dart';
import '../../state/favorites_controller.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_navigation.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'order_history_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// When true, hides back navigation and uses as a tab body.
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _handleLogout(BuildContext context) async {
    if (_loggingOut) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('You will need to sign in again to place orders.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Logout',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    setState(() => _loggingOut = true);
    AppFeedback.light();

    try {
      CartScope.maybeOf(context)?.clear();
      FavoritesScope.maybeOf(context)?.clear();
      await UserFCMService.removeToken();
      await AuthService.logout();
      // AuthGate shows Login; clear pushed routes (menu, checkout, etc.).
      AppNavigation.goToAuthRoot();
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.showError(context, AuthService.messageFromError(e));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diet = DietFilterScope.of(context);

    return ListenableBuilder(
      listenable: diet,
      builder: (context, _) {
        return Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFFF7F7F7),
              body: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 20,
                      right: 12,
                      bottom: 24,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (!widget.embedded)
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: AppColors.white,
                                  size: 20,
                                ),
                              ),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Profile',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Your Available Profile',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EditProfileScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.edit_rounded,
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _ProfileUserHeader(cart: CartScope.maybeOf(context)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        children: [
                          // ── Subscription status card ─────────────────────
                          _SubscriptionCard(),
                          const SizedBox(height: 16),
                          // ── Wallet balance card ──────────────────────────
                          _WalletCard(),
                          const SizedBox(height: 16),
                          // ── Menu card ────────────────────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  value: diet.isVegMode,
                                  onChanged: (v) {
                                    AppFeedback.selection();
                                    diet.setVegMode(v);
                                  },
                                  activeThumbColor: AppColors.primary,
                                  activeTrackColor: AppColors.primary
                                      .withValues(alpha: 0.35),
                                  secondary: Icon(
                                    diet.isVegMode
                                        ? Icons.eco_rounded
                                        : Icons.restaurant_rounded,
                                    color: diet.isVegMode
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFFB71C1C),
                                  ),
                                  title: Text(
                                    diet.isVegMode
                                        ? 'Veg Mode'
                                        : 'Non Veg Mode',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    diet.isVegMode
                                        ? 'Showing veg items app-wide'
                                        : 'Showing non-veg items app-wide',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 1),
                                _MenuTile(
                                  icon: Icons.favorite_border_rounded,
                                  label: 'Favourites',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const FavoritesScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                _MenuTile(
                                  icon: Icons.shopping_bag_outlined,
                                  label: 'Orders',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const OrderHistoryScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                _MenuTile(
                                  icon: Icons.settings_outlined,
                                  label: 'Setting',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SettingsScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                _MenuTile(
                                  icon: Icons.logout_rounded,
                                  label: 'Logout',
                                  danger: true,
                                  onTap: () => _handleLogout(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loggingOut)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.white),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileUserHeader extends StatelessWidget {
  const _ProfileUserHeader({this.cart});

  final CartController? cart;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data ?? AuthService.currentUser;
        final uid = user?.uid;

        // Wrap in a Firestore customer-doc stream so name/email/phone saved
        // during edit or checkout are reflected here immediately without
        // waiting for Firebase Auth to re-emit.
        return StreamBuilder<DocumentSnapshot?>(
          stream: uid != null
              ? FirestoreService.watchCustomerDoc(uid)
              : const Stream.empty(),
          builder: (context, custSnap) {
            final data = custSnap.hasData && custSnap.data!.exists
                ? (custSnap.data!.data() as Map<String, dynamic>? ?? {})
                : <String, dynamic>{};

            final firestoreName = (data['name'] as String? ?? '').trim();
            final firestoreEmail = (data['email'] as String? ?? '').trim();
            final firestorePhone = (data['phone'] as String? ?? '').trim();

            final name = firestoreName.isNotEmpty
                ? firestoreName
                : _displayName(user, cart);
            final email = firestoreEmail.isNotEmpty
                ? firestoreEmail
                : ((user?.email?.trim().isNotEmpty == true)
                      ? user!.email!.trim()
                      : 'No email linked');
            final phone = _displayPhone(user, cart, firestorePhone);

            final photoUrl = user?.photoURL;
            final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

            return Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFFFFE8E8),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? null
                      : Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                          ),
                        ),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }, // custSnap builder
        ); // watchCustomerDoc StreamBuilder
      },
    ); // authState StreamBuilder
  }

  static String _displayName(User? user, CartController? cart) {
    final fromAuth = user?.displayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    final fromCart = cart?.customerName.trim();
    if (fromCart != null &&
        fromCart.isNotEmpty &&
        fromCart != 'Guest User' &&
        !fromCart.startsWith('guest_')) {
      return fromCart;
    }

    final email = user?.email?.trim();
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Customer';
  }

  static String _displayPhone(
    User? user,
    CartController? cart,
    String firestorePhone,
  ) {
    // Priority: Firestore customers doc → Firebase Auth → cart controller.
    if (firestorePhone.isNotEmpty) return firestorePhone;

    final fromAuth = user?.phoneNumber?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    final fromCart = cart?.customerPhone.trim();
    if (fromCart != null &&
        fromCart.isNotEmpty &&
        fromCart != '+91 00000 00000') {
      return fromCart;
    }
    return '';
  }
}

class _SubscriptionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirestoreService.watchCustomerDoc(uid),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final account = CustomerAccount.fromMap(
          uid,
          snap.data!.data() as Map<String, dynamic>? ?? {},
        );

        // Only show the card when a subscription has been purchased at least once.
        final hasAny = account.subscriptionPlanId?.isNotEmpty == true;
        if (!hasAny) return const SizedBox.shrink();

        final isActive = account.hasActiveSubscription;
        final expiry = account.subscribedUntil;
        final planName =
            account.subscriptionPlanName ??
            account.subscriptionPlanId ??
            'Subscription';

        String expiryLabel = '';
        if (expiry != null) {
          final d = expiry;
          expiryLabel = 'Valid until ${d.day} ${_monthName(d.month)} ${d.year}';
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isActive
                  ? [const Color(0xFFB32B2C), const Color(0xFF8B1F20)]
                  : [const Color(0xFF9E9E9E), const Color(0xFF757575)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isActive ? AppColors.primary : Colors.grey).withValues(
                  alpha: 0.2,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive
                      ? Icons.verified_rounded
                      : Icons.card_membership_rounded,
                  color: AppColors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? planName : '$planName (Expired)',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (expiryLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        expiryLabel,
                        style: TextStyle(
                          color: AppColors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (isActive) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '✓ Free Delivery Active',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return month >= 1 && month <= 12 ? months[month] : '';
  }
}

// ── Wallet balance card ───────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<int>(
      stream: WalletService.watchBalance(uid),
      builder: (context, snap) {
        final balance = snap.data ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Wallet icon circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // Labels
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TastyKart Wallet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData
                        ? const SizedBox(
                            width: 60,
                            height: 14,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.white54,
                              ),
                            ),
                          )
                        : Text(
                            '₹$balance',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ],
                ),
              ),
              // "Available balance" chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Available',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: danger ? AppColors.error : const Color(0xFF1A1A1A),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.error : const Color(0xFF1A1A1A),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: danger ? AppColors.error : const Color(0xFFAAAAAA),
      ),
      onTap: onTap,
    );
  }
}
