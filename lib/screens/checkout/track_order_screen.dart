import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../../utils/app_feedback.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/order_tracking_map.dart';
import '../Home/home_screen.dart';
import '../order/delivered_screen.dart';
import 'order_chat_screen.dart';

class TrackOrderScreen extends StatefulWidget {
  const TrackOrderScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  TkOrder? _order;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final id = widget.orderId ?? '';
    if (id.isEmpty) {
      _loading = false;
      return;
    }
    FirestoreService.watchOrder(id).listen((snap) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (snap.exists) _order = TkOrder.fromDoc(snap);
      });
    });
  }

  void _goHome() {
    CartScope.maybeOf(context)?.clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedId = widget.orderId ?? '';
    if (resolvedId.isEmpty) {
      return const _StaticFallback();
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: Column(
          children: [
            AppScreenHeader(
              title: 'Track Your Order',
              subtitle: 'Loading order details…',
              onBack: _goHome,
            ),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    return _TrackingBody(
      order: _order,
      orderId: resolvedId,
      onGoHomeOverride: _goHome,
    );
  }
}

// ── Main tracking body ────────────────────────────────────────────────────────

class _TrackingBody extends StatefulWidget {
  const _TrackingBody({
    required this.order,
    required this.orderId,
    required this.onGoHomeOverride,
  });

  final TkOrder? order;
  final String orderId;
  final VoidCallback onGoHomeOverride;

  @override
  State<_TrackingBody> createState() => _TrackingBodyState();
}

class _TrackingBodyState extends State<_TrackingBody> {
  // Maps status + deliveryStage to a step index (0-based).
  static const _steps = [
    _Step('Order Placed', 'Your order has been placed'),
    _Step('Accepted', 'Restaurant confirmed your order'),
    _Step('Preparing', 'Kitchen is preparing your food'),
    _Step('Out for Delivery', 'Delivery partner is on the way'),
    _Step('Delivered', 'Your order has been delivered 🎉'),
  ];

  /// Whether a cancellation is currently being processed.
  bool _cancelling = false;

  /// Set after a successful cancellation — drives the refund notice.
  CancelOrderResult? _cancelResult;

  int get _currentStep {
    final status = widget.order?.status.toLowerCase() ?? 'pending';
    final stage = widget.order?.deliveryStage.toLowerCase() ?? '';
    if (status == 'delivered') return 4;
    if (status == 'picked' ||
        stage == 'to_customer' ||
        stage == 'arrived_customer') {
      return 3;
    }
    if (status == 'preparing' ||
        stage == 'preparing' ||
        stage == 'pickup' ||
        stage == 'at_restaurant') {
      return 2;
    }
    if (status == 'accepted' || stage == 'to_restaurant') return 1;
    return 0; // pending
  }

  bool get _isDelivered => widget.order?.status.toLowerCase() == 'delivered';
  bool get _isCancelled => widget.order?.status.toLowerCase() == 'cancelled';

  /// Only show the cancel button before the partner picks the food.
  bool get _canCancel {
    final status = widget.order?.status.toLowerCase() ?? '';
    return const {'pending', 'accepted', 'preparing'}.contains(status);
  }

  // ── Cancel flow ────────────────────────────────────────────────────────────

  Future<void> _onCancelTapped() async {
    AppFeedback.light();

    // Show reason picker bottom sheet.
    final reason = await _CancelReasonSheet.show(context);
    if (reason == null || !mounted) return; // user dismissed

    setState(() => _cancelling = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await FirestoreService.cancelOrderByUser(
        orderId: widget.orderId,
        customerId: uid,
        cancelReason: reason,
      );

      if (!mounted) return;

      if (result.success) {
        AppFeedback.success();
        setState(() => _cancelResult = result);
        // Show the post-cancellation notice instead of navigating away —
        // the StreamBuilder will also flip to _CancelledOrderBody on the
        // next Firestore snapshot, but we show our richer notice first.
        if (mounted) {
          await _PostCancelDialog.show(context, result: result);
        }
      } else {
        AppFeedback.showError(
          context,
          result.error ?? 'Could not cancel order. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(
          context,
          'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.maybeOf(context);
    // Address: prefer live order doc (survives cart.clear()), fall back to cart, then placeholder.
    final address = (widget.order?.address.isNotEmpty == true)
        ? widget.order!.address
        : (cart?.selectedAddress?.fullAddress ?? '');
    final total = widget.order?.total ?? cart?.grandTotal ?? 0;
    final otp = widget.order?.deliveryOtp ?? '';
    final partnerName = widget.order?.deliveryPartnerName ?? '';
    final partnerPhone = widget.order?.deliveryPartnerPhone ?? '';
    final partnerId = widget.order?.deliveryPartnerId ?? '';
    // Map coords: prefer order's stored destLat/destLng, fall back to live cart address coords.
    final destLat = widget.order?.destLat ?? cart?.selectedAddress?.lat;
    final destLng = widget.order?.destLng ?? cart?.selectedAddress?.lng;

    void goHome() => widget.onGoHomeOverride();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: _isCancelled ? 'Order Cancelled' : 'Track Your Order',
            subtitle: widget.orderId,
            onBack: goHome,
          ),

          // ── Cancelled state: replace entire body ─────────────────────
          if (_isCancelled)
            Expanded(
              child: _CancelledOrderBody(
                orderId: widget.orderId,
                order: widget.order,
                address: address,
                total: total,
                cancelResult: _cancelResult,
                onGoHome: goHome,
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Map ────────────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: OrderTrackingMap(
                      height: 220,
                      destinationLat: destLat,
                      destinationLng: destLng,
                      destinationAddress: address.isNotEmpty ? address : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── OTP card (shown until delivered) ───────────────
                  if (otp.isNotEmpty && !_isDelivered) _OtpCard(otp: otp),
                  if (otp.isNotEmpty && !_isDelivered)
                    const SizedBox(height: 16),

                  // ── Delivery stage tracker ─────────────────────────
                  _StageTracker(currentStep: _currentStep, steps: _steps),
                  const SizedBox(height: 16),

                  // ── Order info card ────────────────────────────────
                  _OrderInfoCard(
                    orderId: widget.orderId,
                    address: address.isNotEmpty
                        ? address
                        : 'Address not available',
                    total: total,
                    walletUsed: widget.order?.walletUsed ?? 0,
                    partnerName: partnerName,
                    partnerPhone: partnerPhone,
                    partnerId: partnerId,
                  ),
                  const SizedBox(height: 20),

                  // ── Delivered: show Rate Experience ────────────────
                  if (_isDelivered)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          cart?.clear();
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeliveredScreen(
                                orderId: widget.order?.id.isNotEmpty == true
                                    ? widget.order!.id
                                    : widget.orderId,
                                restaurantId: widget.order?.restaurantId ?? '',
                                restaurantName:
                                    widget.order?.restaurantName ?? '',
                                customerId: widget.order?.customerId ?? '',
                                customerName: widget.order?.customerName ?? '',
                                deliveryPartnerId:
                                    widget.order?.deliveryPartnerId ?? '',
                                deliveryPartnerName:
                                    widget.order?.deliveryPartnerName ?? '',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Rate Your Experience',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),

                  // ── Cancel Order button (pre-pickup only) ──────────
                  if (_canCancel && !_isDelivered) ...[
                    const SizedBox(height: 12),
                    _CancelOrderButton(
                      loading: _cancelling,
                      onTap: _cancelling ? null : _onCancelTapped,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Cancelled order body ──────────────────────────────────────────────────────

class _CancelledOrderBody extends StatelessWidget {
  const _CancelledOrderBody({
    required this.orderId,
    required this.order,
    required this.address,
    required this.total,
    required this.onGoHome,
    this.cancelResult,
  });

  final String orderId;
  final TkOrder? order;
  final String address;
  final int total;
  final VoidCallback onGoHome;

  /// If the cancellation was just triggered from this screen, we have the
  /// full result (refundEligible, paymentMethod, etc.) for the notice.
  final CancelOrderResult? cancelResult;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        // ── Cancelled icon banner ────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECEC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel_rounded,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Order Cancelled',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your order has been cancelled.\nIf you were charged, a refund will be processed shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMedium,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Refund notice (shown right after user-initiated cancel) ──
        if (cancelResult != null) ...[
          _RefundNoticeCard(result: cancelResult!),
          const SizedBox(height: 16),
        ],

        // ── Order status tracker showing cancelled ───────────────────
        _CancelledStageTracker(),
        const SizedBox(height: 16),

        // ── Order summary ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const Divider(height: 20),
              _SummaryRow('Order ID', orderId),
              if (order?.restaurantName.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _SummaryRow('Restaurant', order!.restaurantName),
              ],
              if (address.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SummaryRow('Address', address, maxLines: 2),
              ],
              const SizedBox(height: 8),
              // order.total is already post-wallet. Show pre-wallet amount so the
              // math is transparent: Amount - Wallet Applied = Amount Due.
              if (order?.walletUsed != null && order!.walletUsed > 0) ...[
                _SummaryRow('Amount', '₹${total + order!.walletUsed}'),
                const SizedBox(height: 4),
                _SummaryRow(
                  '  Wallet Applied',
                  '- ₹${order!.walletUsed}',
                  accent: true,
                ),
                const SizedBox(height: 4),
                _SummaryRow('Amount Due', '₹$total', accent: true),
              ] else ...[
                _SummaryRow('Amount', '₹$total'),
              ],
              if (order?.paymentMethod.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _SummaryRow('Payment', order!.paymentMethod),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ── Go Home button ───────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onGoHome,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Go to Home',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _CancelledStageTracker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Status',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(
                  Icons.cancel_rounded,
                  size: 16,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cancelled',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Your order has been cancelled',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
    this.label,
    this.value, {
    this.maxLines = 1,
    this.accent = false,
  });
  final String label;
  final String value;
  final int maxLines;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: accent ? const Color(0xFF1565C0) : AppColors.textMedium,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: accent ? const Color(0xFF1565C0) : AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

// ── OTP card ──────────────────────────────────────────────────────────────────

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.otp});
  final String otp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery OTP',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Share this with your delivery partner',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: otp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('OTP copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: AppColors.textMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: otp.split('').map((digit) {
              return Container(
                width: 52,
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Stage tracker ─────────────────────────────────────────────────────────────

class _Step {
  final String label;
  final String subtitle;
  const _Step(this.label, this.subtitle);
}

class _StageTracker extends StatelessWidget {
  const _StageTracker({required this.currentStep, required this.steps});

  final int currentStep;
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Status',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (i) {
            final done = i < currentStep;
            final current = i == currentStep;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dot + connector
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? AppColors.success
                            : current
                            ? AppColors.primary
                            : const Color(0xFFEEEEEE),
                        boxShadow: current
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        done
                            ? Icons.check_rounded
                            : current
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: done ? 16 : 10,
                        color: done || current
                            ? AppColors.white
                            : const Color(0xFFBBBBBB),
                      ),
                    ),
                    if (i < steps.length - 1)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 2,
                        height: 32,
                        color: done
                            ? AppColors.success
                            : const Color(0xFFEEEEEE),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3, bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: current || done
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: current
                                ? AppColors.primary
                                : done
                                ? AppColors.textDark
                                : AppColors.textLight,
                          ),
                        ),
                        if (current)
                          Text(
                            steps[i].subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Order info card ───────────────────────────────────────────────────────────

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({
    required this.orderId,
    required this.address,
    required this.total,
    required this.partnerName,
    required this.partnerPhone,
    required this.partnerId,
    this.walletUsed = 0,
  });

  final String orderId;
  final String address;
  final int total;
  final int walletUsed;
  final String partnerName;
  final String partnerPhone;
  final String partnerId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Order ID', orderId),
          const Divider(height: 20),
          _row('Delivery Address', address, maxLines: 2),
          const Divider(height: 20),
          // order.total is already post-wallet. Show pre-wallet amount so the
          // breakdown is: Amount - Wallet Used = Amount Due (what they actually pay).
          if (walletUsed > 0) ...[
            _row('Amount', '₹${total + walletUsed}'),
            const SizedBox(height: 6),
            _row('  Wallet Applied', '- ₹$walletUsed', accent: true),
            const SizedBox(height: 6),
            _row('Amount Due', '₹$total', accent: true),
          ] else ...[
            _row('Amount', '₹$total'),
          ],
          if (partnerName.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFFFE8E8),
                  child: Icon(
                    Icons.delivery_dining_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partnerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const Text(
                        'Delivery Partner',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Call button ────────────────────────────────
                if (partnerPhone.isNotEmpty)
                  _ActionButton(
                    icon: Icons.call_rounded,
                    color: AppColors.success,
                    onTap: () async {
                      final uri = Uri.parse('tel:$partnerPhone');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                const SizedBox(width: 8),
                // ── Chat button ────────────────────────────────
                _ActionButton(
                  icon: Icons.chat_rounded,
                  color: AppColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderChatScreen(
                        orderId: orderId,
                        partnerName: partnerName,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    int maxLines = 1,
    bool accent = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: accent ? const Color(0xFF1565C0) : AppColors.textMedium,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: accent ? const Color(0xFF1565C0) : AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Compact action icon button ────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ── Cancel Order button ───────────────────────────────────────────────────────

class _CancelOrderButton extends StatelessWidget {
  const _CancelOrderButton({required this.onTap, this.loading = false});

  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Cancel Order',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Cancel reason bottom sheet ────────────────────────────────────────────────

class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet();

  /// Shows the sheet and returns the selected reason string, or null if
  /// the user dismissed without selecting.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CancelReasonSheet(),
    );
  }

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  static const _reasons = [
    'Changed my mind',
    'Ordered by mistake',
    'Delivery is taking too long',
    'Found a better option',
    'Address entered incorrectly',
    'Other',
  ];

  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Why are you cancelling?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'This helps us improve your experience.',
            style: TextStyle(fontSize: 13, color: AppColors.textMedium),
          ),
          const SizedBox(height: 16),

          // Reason list
          ..._reasons.map((reason) {
            final selected = _selected == reason;
            return GestureDetector(
              onTap: () => setState(() => _selected = reason),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.07)
                      : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFEEEEEE),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: const Color(0xFFDDDDDD),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Confirm Cancellation',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Post-cancel dialog (refund notice) ────────────────────────────────────────

class _PostCancelDialog extends StatelessWidget {
  const _PostCancelDialog({required this.result});

  final CancelOrderResult result;

  static Future<void> show(
    BuildContext context, {
    required CancelOrderResult result,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PostCancelDialog(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCOD = !result.refundEligible;
    final walletUsed = result.walletUsed;
    final isCODWithWallet = isCOD && walletUsed > 0;
    // For non-COD: full refund = total (post-wallet cash) + walletUsed
    final onlineRefundAmt = result.total + walletUsed;

    // Derive display values per scenario
    final Color iconBg = isCODWithWallet
        ? const Color(0xFFE8F5E9)
        : isCOD
        ? const Color(0xFFFFECEC)
        : const Color(0xFFFFF8E1);
    final Color iconColor = isCODWithWallet
        ? const Color(0xFF2E7D32)
        : isCOD
        ? AppColors.primary
        : const Color(0xFFF9A825);
    final IconData iconData = isCODWithWallet
        ? Icons.account_balance_wallet_rounded
        : isCOD
        ? Icons.cancel_rounded
        : Icons.account_balance_wallet_rounded;
    final String title = isCODWithWallet
        ? 'Order Cancelled — Wallet Refunded'
        : isCOD
        ? 'Order Cancelled'
        : 'Order Cancelled — Refund Initiated';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(iconData, color: iconColor, size: 32),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),

          // Body text — three cases
          if (isCODWithWallet) ...[
            // COD + wallet: wallet portion is auto-refunded, no online refund
            Text(
              '₹$walletUsed wallet credit has been automatically added back to your TastyKart wallet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMedium,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: Color(0xFF2E7D32),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No cash refund is needed for a COD order. Only your wallet credit has been returned.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1B5E20),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isCOD) ...[
            // Pure COD, no wallet — nothing to refund
            const Text(
              'Your order has been cancelled. Since this was a cash on delivery order, no refund is required.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMedium,
                height: 1.5,
              ),
            ),
          ] else ...[
            // Online payment (non-COD) — full refund requested
            Text(
              '₹$onlineRefundAmt will be credited to your TastyKart wallet after admin approval.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMedium,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFF9A825),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The refund will be credited to your TastyKart wallet within a few minutes after admin approval.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A5F00),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Partner notice
          if (result.partnerWasAssigned) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.delivery_dining_rounded,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.partnerName.isNotEmpty
                          ? '${result.partnerName} has been notified not to pick up this order.'
                          : 'The delivery partner has been notified not to pick up this order.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E7D32),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Refund notice card (shown in CancelledOrderBody) ──────────────────────────

class _RefundNoticeCard extends StatelessWidget {
  const _RefundNoticeCard({required this.result});

  final CancelOrderResult result;

  @override
  Widget build(BuildContext context) {
    final isCOD = !result.refundEligible;
    final walletUsed = result.walletUsed;
    // COD + wallet applied: wallet portion is auto-refunded, no online refund
    final isCODWithWallet = isCOD && walletUsed > 0;
    // Online payment (non-COD): full amount (total + walletUsed) refunded
    final onlineRefundAmt = result.total + walletUsed;

    // Colour scheme
    final Color bgColor = isCODWithWallet
        ? const Color(0xFFE8F5E9) // green-tinted for wallet refunded
        : isCOD
        ? const Color(0xFFFFF3E0) // orange for no refund
        : const Color(0xFFFFF8E1); // yellow for online refund pending
    final Color borderColor = isCODWithWallet
        ? const Color(0xFFA5D6A7)
        : isCOD
        ? const Color(0xFFFFCC80)
        : const Color(0xFFFFE082);
    final Color accentColor = isCODWithWallet
        ? const Color(0xFF2E7D32)
        : isCOD
        ? const Color(0xFFE65100)
        : const Color(0xFFF9A825);
    final IconData iconData = isCODWithWallet
        ? Icons.account_balance_wallet_rounded
        : isCOD
        ? Icons.money_off_rounded
        : Icons.account_balance_wallet_rounded;

    final String title = isCODWithWallet
        ? '💙 Wallet Credit Refunded'
        : isCOD
        ? 'No Refund (COD order)'
        : 'Refund Requested';

    final String message = isCODWithWallet
        ? '₹$walletUsed wallet credit has been automatically added back to your TastyKart wallet.'
        : isCOD
        ? 'This was a cash on delivery order — no payment was collected online.'
        : '₹$onlineRefundAmt will be credited to your TastyKart wallet after admin approval.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fallback when no orderId ──────────────────────────────────────────────────

class _StaticFallback extends StatelessWidget {
  const _StaticFallback();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Track Your Order',
            subtitle: 'Your order is being processed',
            onBack: () {
              CartScope.maybeOf(context)?.clear();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
              );
            },
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Locating your order…',
                style: TextStyle(color: AppColors.textMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
