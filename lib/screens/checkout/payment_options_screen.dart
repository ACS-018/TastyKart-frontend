import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../services/firestore_service.dart';
import '../../services/razorpay_payment_service.dart';
import '../../state/cart_controller.dart';
import 'card_details_screen.dart';
import 'track_order_screen.dart';

class PaymentOptionsScreen extends StatefulWidget {
  const PaymentOptionsScreen({super.key});

  @override
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen> {
  String _selected = 'gpay';
  bool _paying = false;
  final RazorpayPaymentService _razorpay = RazorpayPaymentService();

  String get _methodLabel {
    switch (_selected) {
      case 'phonepe':
        return 'PhonePe';
      case 'gpay':
        return 'Google Pay';
      case 'paytm':
        return 'Paytm';
      case 'card':
        return 'Card';
      default:
        return 'UPI';
    }
  }

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  Future<void> _completePayment() async {
    if (_paying) return;

    final user = FirebaseAuth.instance.currentUser;
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
    if (cart.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your cart is empty'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Keep customerId aligned with Auth for Cloud Function ownership checks.
    cart.setCustomer(
      id: user.uid,
      name: cart.customerName.isNotEmpty && !cart.customerName.startsWith('Guest')
          ? cart.customerName
          : (user.displayName ?? user.email ?? 'Customer'),
      phone: cart.customerPhone.isNotEmpty &&
              !cart.customerPhone.contains('00000')
          ? cart.customerPhone
          : (user.phoneNumber ?? cart.customerPhone),
    );

    setState(() => _paying = true);
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';

    try {
      // 1) Create Firestore order draft (no payment truth fields from client).
      await FirestoreService.createOrder(
        cart.toAdminOrderPayload(
          paymentMethod: 'Razorpay ($_methodLabel)',
          orderId: orderId,
        ),
      );

      // 2–4) CF create → Checkout → CF verify
      final result = await _razorpay.payForOrder(
        orderId: orderId,
        customerName: cart.customerName,
        customerContact: cart.customerPhone,
        customerEmail: user.email,
        preferredMethodLabel: _methodLabel,
      );

      if (!mounted) return;

      if (result.isFullyVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TrackOrderScreen(orderId: orderId),
          ),
        );
        return;
      }

      final reason = result.reason ?? 'Payment not verified';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.razorpayPaymentId != null && !result.verified
                ? 'Payment received but not verified yet. '
                    'If money was deducted, it will confirm shortly. ($reason)'
                : 'Payment unsuccessful: $reason',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          _Header(
            title: 'Add Payment Options',
            subtitle: 'Choose Your Payment Option',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pay By UPI App',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PayTile(
                        id: 'phonepe',
                        selected: _selected,
                        label: 'PhonePe',
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFF5F259F),
                        onTap: () => setState(() => _selected = 'phonepe'),
                      ),
                      _PayTile(
                        id: 'gpay',
                        selected: _selected,
                        label: 'Google Pay',
                        icon: Icons.g_mobiledata_rounded,
                        color: const Color(0xFF4285F4),
                        onTap: () => setState(() => _selected = 'gpay'),
                      ),
                      _PayTile(
                        id: 'upi',
                        selected: _selected,
                        label: 'UPI',
                        icon: Icons.qr_code_rounded,
                        color: AppColors.primary,
                        onTap: () => setState(() => _selected = 'upi'),
                      ),
                      _PayTile(
                        id: 'paytm',
                        selected: _selected,
                        label: 'Paytm',
                        icon: Icons.currency_rupee_rounded,
                        color: const Color(0xFF00BAF2),
                        onTap: () => setState(() => _selected = 'paytm'),
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Credit & Debit Cards',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFE8E8),
                          child: Icon(
                            Icons.credit_card_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        title: const Text(
                          '+ Add New Card',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text('Save And Pay Via Cards'),
                        trailing: Radio<String>(
                          value: 'card',
                          groupValue: _selected,
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _selected = v);
                          },
                        ),
                        onTap: () async {
                          setState(() => _selected = 'card');
                          final paid = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CardDetailsScreen(),
                            ),
                          );
                          if (paid == true && context.mounted) {
                            await _completePayment();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_selected != 'card')
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _paying ? null : _completePayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
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
                        : const Text(
                            'Pay Now',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
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

class _PayTile extends StatelessWidget {
  const _PayTile({
    required this.id,
    required this.selected,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String id;
  final String selected;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Radio<String>(
        value: id,
        groupValue: selected,
        activeColor: AppColors.primary,
        onChanged: (_) => onTap(),
      ),
      onTap: onTap,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 16,
        bottom: 18,
      ),
      color: AppColors.primary,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.white, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
