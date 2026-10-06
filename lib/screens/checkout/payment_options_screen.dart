import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/color_constants.dart';
import '../../models/customer_account.dart';
import '../../services/auth_service.dart';
import '../../services/customer_account_service.dart';
import '../../services/firestore_service.dart';
import '../../services/razorpay_payment_service.dart';
import '../../services/wallet_service.dart';
import '../../state/cart_controller.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_navigation.dart';
import 'track_order_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Payment options screen
//
// Flow:
//   Online Payment → Razorpay checkout (UPI / Cards / Net Banking / Wallet)
//                  → Cloud Function verifies payment server-side
//                  → ONLY after full verification → create Firestore order
//
//   Cash on Delivery → create order immediately, no payment gateway
// ─────────────────────────────────────────────────────────────────────────────

class PaymentOptionsScreen extends StatefulWidget {
  const PaymentOptionsScreen({super.key});

  @override
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen> {
  /// 'online' or 'cod'
  String _selected = 'online';

  bool _paying = false;
  final RazorpayPaymentService _razorpay = RazorpayPaymentService();
  User? _user;

  bool get _isCod => _selected == 'cod';

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
  }

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  // ── Payment orchestration ───────────────────────────────────────────────────

  Future<void> _completePayment() async {
    if (_paying) return;

    final user = _user ?? FirebaseAuth.instance.currentUser;
    debugPrint('[Pay] ── Pay Now tapped ──────────────────────────────────');
    debugPrint(
      '[Pay] method=$_selected isCod=$_isCod user=${user?.uid ?? "null"}',
    );

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to place an order'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final cart = CartScope.of(context);
    debugPrint(
      '[Pay] cart.lines=${cart.lines.length} '
      'itemsTotal=₹${cart.itemsTotal} '
      'deliveryFee=₹${cart.deliveryFee} '
      'tax=₹${cart.taxes} '
      'platformFee=₹${cart.platformFee} '
      'discount=₹${cart.discount} '
      'tip=₹${cart.tipAmount} '
      'walletApplied=₹${cart.walletApplied} '
      'grandTotal=₹${cart.grandTotal}',
    );
    debugPrint(
      '[Pay] hasAddress=${cart.hasDeliveryAddress} '
      'address="${cart.selectedAddress?.fullAddress ?? "none"}"',
    );

    if (cart.lines.isEmpty) {
      debugPrint('[Pay] ❌ cart is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your cart is empty'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!cart.hasDeliveryAddress) {
      debugPrint('[Pay] ❌ no delivery address');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add a delivery address before placing an order',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _paying = true);

    try {
      // ── 1. Enforce customer access ───────────────────────────────────────
      debugPrint('[Pay] step 1 → enforcing customer access');
      try {
        await AuthService.enforceCustomerAccess(user);
        debugPrint('[Pay] step 1 ✅ customer access OK');
      } on CustomerBlockedException catch (e) {
        debugPrint('[Pay] step 1 ❌ customer blocked: ${e.message}');
        cart.clear();
        if (!mounted) return;
        AppFeedback.showError(context, e.message);
        AppNavigation.goToAuthRoot();
        return;
      }

      // ── 2. Resolve phone ────────────────────────────────────────────────
      debugPrint('[Pay] step 2 → resolving phone');
      final customerAccount = await CustomerAccountService.fetchLatestForUser(
        user,
      );
      final resolvedPhone = _resolvePhone(
        firestorePhone: customerAccount?.phone,
        authPhone: user.phoneNumber,
        cartPhone: cart.customerPhone,
      );
      debugPrint('[Pay] step 2 ✅ phone="$resolvedPhone"');

      cart.setCustomer(
        id: user.uid,
        name:
            cart.customerName.isNotEmpty &&
                !cart.customerName.startsWith('Guest')
            ? cart.customerName
            : (user.displayName ?? user.email ?? 'Customer'),
        phone: resolvedPhone,
      );

      // ── 3. Phone gate ────────────────────────────────────────────────────
      String finalPhone = resolvedPhone;
      if (finalPhone.isEmpty) {
        debugPrint('[Pay] step 3 → phone empty, showing dialog');
        if (!mounted) return;
        final entered = await _showPhoneDialog();
        if (!mounted) return;
        if (entered == null || entered.isEmpty) {
          debugPrint('[Pay] step 3 ❌ phone dialog cancelled');
          return;
        }
        await FirestoreService.updateCustomerPhone(
          uid: user.uid,
          phone: entered,
        );
        finalPhone = entered;
        cart.setCustomer(
          id: user.uid,
          name: cart.customerName,
          phone: finalPhone,
        );
        debugPrint('[Pay] step 3 ✅ phone set to "$finalPhone"');
      }

      final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('[Pay] orderId=$orderId');

      // ── 4a. Wallet-only (grandTotal = 0, wallet covers everything) ─────────
      if (cart.grandTotal == 0 && cart.walletApplied > 0) {
        debugPrint(
          '[Pay] step 4a → wallet-only order (grandTotal=0, wallet=₹${cart.walletApplied})',
        );
        await FirestoreService.createOrder(
          cart.toAdminOrderPayload(paymentMethod: 'Wallet', orderId: orderId),
        );
        debugPrint('[Pay] step 4a ✅ Firestore order created');
        await WalletService.deduct(uid: user.uid, amount: cart.walletApplied);
        debugPrint('[Pay] step 4a ✅ wallet deducted');
        cart.clear();
        if (!mounted) return;
        AppFeedback.showSuccess(context, 'Order placed using wallet balance');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
        );
        return;
      }

      // ── 4b. Cash on Delivery ─────────────────────────────────────────────
      if (_isCod) {
        debugPrint(
          '[Pay] step 4b → COD order (method=$_selected wallet=₹${cart.walletApplied})',
        );
        await FirestoreService.createOrder(
          cart.toAdminOrderPayload(
            paymentMethod: 'Cash on Delivery',
            orderId: orderId,
          ),
        );
        debugPrint('[Pay] step 4b ✅ Firestore order created');
        if (cart.walletApplied > 0) {
          await WalletService.deduct(uid: user.uid, amount: cart.walletApplied);
          debugPrint('[Pay] step 4b ✅ wallet deducted ₹${cart.walletApplied}');
        }
        cart.clear();
        if (!mounted) return;
        AppFeedback.showSuccess(context, 'Order placed — pay cash on delivery');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
        );
        return;
      }

      // ── 4c. Online Payment via Razorpay ──────────────────────────────────
      //
      // The placeholder is written to `pendingPayments` (NOT `orders`) so it
      // is invisible to the admin panel.  The Cloud Function `applyPaidUpdate`
      // promotes it to `orders` only after full server-side verification.
      //
      // Flow:
      //   a) Write placeholder to pendingPayments/{orderId}
      //   b) CF createRazorpayOrder reads amount from pendingPayments
      //   c) User completes payment
      //   d) CF verifyRazorpayPayment promotes doc to orders + deletes pending
      //   e) If cancelled/failed → pending doc stays in pendingPayments (not in orders)

      // Step 1: Write placeholder to pendingPayments (never visible in admin)
      debugPrint('[Pay] step 4c → creating placeholder in pendingPayments');
      await FirebaseFirestore.instance
          .collection('pendingPayments')
          .doc(orderId)
          .set({
            ...cart.toAdminOrderPayload(
              paymentMethod: 'Online Payment',
              orderId: orderId,
              extraFields: const {
                'paymentStatus': 'pending_razorpay',
                'paymentVerified': false,
                'isPlaceholder': true,
              },
            ),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      debugPrint('[Pay] step 4c ✅ Placeholder written to pendingPayments');

      // Print breakdown for debugging
      final subtotal = cart.itemsTotal;
      final tax = cart.taxes;
      final deliveryFee = cart.deliveryFee;
      final platformFee = cart.platformFee;
      final discount = cart.discount;
      final tip = cart.tipAmount;
      final wallet = cart.walletApplied;
      final serverRecompute =
          subtotal + tax + deliveryFee + platformFee - discount + tip - wallet;
      debugPrint(
        '[Pay]   server_recompute: '
        'subtotal=$subtotal + tax=$tax + fee=$deliveryFee + platform=$platformFee '
        '- discount=$discount + tip=$tip - wallet=$wallet = $serverRecompute '
        '(grandTotal=${cart.grandTotal}, diff=${serverRecompute - cart.grandTotal})',
      );

      // Step 2: Open Razorpay checkout
      debugPrint('[Pay] step 4c → opening Razorpay checkout');
      final result = await _razorpay.payForOrder(
        orderId: orderId,
        customerName: cart.customerName,
        customerContact: finalPhone,
        customerEmail: user.email,
        preferredMethodLabel: 'Online Payment',
      );
      debugPrint(
        '[Pay] step 4c ← Razorpay result: '
        'success=${result.success} '
        'verified=${result.verified} '
        'isFullyVerified=${result.isFullyVerified} '
        'paymentId=${result.razorpayPaymentId} '
        'reason=${result.reason}',
      );

      if (!mounted) return;

      // Step 3: Handle result
      if (result.isFullyVerified) {
        debugPrint(
          '[Pay] step 4c ✅ payment verified — CF promoted pendingPayments → orders',
        );
        // CF verifyRazorpayPayment already promoted the doc to orders.
        // Just deduct wallet (if any) and navigate.
        if (cart.walletApplied > 0) {
          await WalletService.deduct(uid: user.uid, amount: cart.walletApplied);
          debugPrint('[Pay] step 4c ✅ wallet deducted ₹${cart.walletApplied}');
        }

        cart.clear();
        if (!mounted) return;
        debugPrint('[Pay] ✅ navigating to TrackOrderScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
        );
        return;
      }

      // ❌ Payment failed / cancelled / unverified
      debugPrint('[Pay] step 4c ❌ payment not fully verified');

      // Check if payment ID exists (money might have been deducted)
      if (result.razorpayPaymentId != null &&
          result.razorpayPaymentId!.isNotEmpty) {
        debugPrint(
          '[Pay] Payment ID exists (${result.razorpayPaymentId}) — '
          'pendingPayments doc stays for webhook reconciliation',
        );

        // The placeholder is already in pendingPayments with the razorpayOrderId.
        // The webhook will call applyPaidUpdate which promotes it to orders
        // automatically if/when the payment clears.
        if (!mounted) return;

        cart.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment is being verified. Your order will be confirmed shortly. '
              'Check your orders page.',
            ),
            duration: Duration(seconds: 6),
            backgroundColor: Colors.orange,
          ),
        );

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: orderId)),
        );
        return;
      }

      // No payment ID — truly cancelled/failed. Delete the pending placeholder.
      debugPrint('[Pay] No payment ID — deleting pendingPayments placeholder');
      try {
        await FirebaseFirestore.instance
            .collection('pendingPayments')
            .doc(orderId)
            .delete();
        debugPrint('[Pay] ✅ pendingPayments placeholder deleted');
      } catch (deleteErr) {
        debugPrint('[Pay] ⚠️  Could not delete placeholder: $deleteErr');
      }

      if (!mounted) return;

      final reason = result.reason ?? '';
      debugPrint('[Pay] showing failure snackbar: reason="$reason"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason.contains('checkout_failed') ||
                    reason.contains('cancelled') ||
                    reason.contains('cancel')
                ? 'Payment cancelled. No order was placed.'
                : 'Payment failed. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('[Pay] ❌ EXCEPTION: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      debugPrint('[Pay] ── done ──────────────────────────────────────────');
      if (mounted) setState(() => _paying = false);
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────────

  Future<String?> _showPhoneDialog() async {
    final formKey = GlobalKey<FormState>();
    final ctrl = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Add Phone Number',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A phone number is required so the restaurant and '
                    'delivery partner can reach you.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ctrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    autofocus: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '9876543210',
                      prefixText: '+91  ',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final digits = (v ?? '').trim();
                      if (digits.length != 10) {
                        return 'Enter exactly 10 digits';
                      }
                      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                        return 'Enter a valid Indian mobile number';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF666666)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(ctx, ctrl.text.trim());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Save & Continue',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  String _resolvePhone({
    String? firestorePhone,
    String? authPhone,
    String? cartPhone,
  }) {
    bool isPlaceholder(String? p) =>
        p == null ||
        p.isEmpty ||
        p.contains('00000') ||
        p.replaceAll(RegExp(r'[\s\+\-\(\)]'), '').replaceAll('0', '').isEmpty;
    if (!isPlaceholder(firestorePhone)) return firestorePhone!;
    if (!isPlaceholder(authPhone)) return authPhone!;
    if (!isPlaceholder(cartPhone)) return cartPhone!;
    return '';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    final grandTotal = cart.grandTotal;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 6,
              left: 4,
              right: 16,
              bottom: 20,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                ),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Choose your payment method',
                      style: TextStyle(color: Color(0xFFFFCDD2), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                // ── Order total summary ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Order Total',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textMedium,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '₹$grandTotal',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── When wallet covers 100% — no payment method needed ─────
                if (grandTotal == 0) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8E6C9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Color(0xFF2E7D32),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Paying with Wallet',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Your wallet balance covers the full order amount.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF388E3C),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ── Payment method card ────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                          child: Text(
                            'Payment Method',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Choose how you want to pay',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF888888),
                            ),
                          ),
                        ),

                        // ── Online Payment ─────────────────────────────────
                        _PaymentTile(
                          id: 'online',
                          selected: _selected,
                          label: 'Online Payment',
                          subtitle: 'UPI · Cards · Net Banking · Wallets',
                          icon: Icons.payment_rounded,
                          iconColor: const Color(0xFF1565C0),
                          iconBg: const Color(0xFFE3F2FD),
                          onTap: () => setState(() => _selected = 'online'),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                        ),

                        // ── Cash on Delivery ───────────────────────────────
                        _PaymentTile(
                          id: 'cod',
                          selected: _selected,
                          label: 'Cash on Delivery',
                          subtitle: 'Pay when your order arrives',
                          icon: Icons.payments_outlined,
                          iconColor: const Color(0xFF2E7D32),
                          iconBg: const Color(0xFFE8F5E9),
                          onTap: () => setState(() => _selected = 'cod'),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Online payment info banner ─────────────────────────────
                  if (!_isCod)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F8FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBD6FF)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: Color(0xFF1565C0),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your order will be placed only after payment is '
                              'successfully verified. Razorpay supports UPI, '
                              'credit/debit cards, net banking, and more.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1565C0),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── COD note ──────────────────────────────────────────────
                  if (_isCod)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC8E6C9)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Color(0xFF2E7D32),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Keep exact change ready. Pay the delivery partner '
                              'when your order arrives.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2E7D32),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ], // end else (grandTotal > 0)
              ],
            ),
          ),

          // ── Pay / Place Order button ─────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _paying ? null : _completePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.6,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _paying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : Text(
                          grandTotal == 0
                              ? 'Place Order — Wallet'
                              : _isCod
                              ? 'Place Order  ₹$grandTotal'
                              : 'Pay Now  ₹$grandTotal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment method tile ───────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.id,
    required this.selected,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
  });

  final String id;
  final String selected;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOn = id == selected;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isOn
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOn
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isOn ? AppColors.primary : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
            // Radio
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOn ? AppColors.primary : const Color(0xFFBBBBBB),
                  width: 2,
                ),
                color: isOn ? AppColors.primary : Colors.transparent,
              ),
              child: isOn
                  ? const Center(
                      child: Icon(Icons.check, size: 13, color: Colors.white),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
