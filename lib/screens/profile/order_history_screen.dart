import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../models/food_item.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/async_state_message.dart';
import '../checkout/cart_summary_screen.dart';
import '../checkout/track_order_screen.dart';

/// Shows orders from Firestore `orders` filtered by the signed-in user's uid
/// (`customerId`), matching how checkout writes orders.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  int _refreshToken = 0;

  Future<void> _onRefresh() async {
    setState(() => _refreshToken++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  String? _resolveCustomerId(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;

    final cartId = CartScope.maybeOf(context)?.customerId;
    if (cartId != null && cartId.isNotEmpty && !cartId.startsWith('guest_')) {
      return cartId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final customerId = _resolveCustomerId(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Order History',
            subtitle: 'All your orders',
            onBack: widget.embedded ? null : () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: customerId == null
                  ? const AsyncStateMessage(
                      icon: Icons.lock_outline_rounded,
                      message: 'Sign in to view your order history.',
                    )
                  : StreamBuilder<QuerySnapshot>(
                      key: ValueKey('${customerId}_$_refreshToken'),
                      stream: FirestoreService.ordersByCustomer(customerId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return AsyncStateMessage(
                            icon: Icons.error_outline_rounded,
                            message: 'Failed to load your orders',
                            actionLabel: 'Try again',
                            onAction: _onRefresh,
                          );
                        }
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const AsyncStateMessage.loading();
                        }

                        final orders =
                            (snapshot.data?.docs ?? [])
                                .map(TkOrder.fromDoc)
                                .where(
                                  (o) =>
                                      o.id.isNotEmpty &&
                                      o.customerId == customerId,
                                )
                                .toList()
                              ..sort((a, b) {
                                final aa =
                                    a.createdAt ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                final bb =
                                    b.createdAt ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                return bb.compareTo(aa);
                              });

                        if (orders.isEmpty) {
                          return RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _onRefresh,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                AsyncStateMessage(
                                  icon: Icons.receipt_long_outlined,
                                  message:
                                      'No orders yet.\nPlace an order and it will show up here.',
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _onRefresh,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              widget.embedded ? 100 : 24,
                            ),
                            itemCount: orders.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) =>
                                _OrderHistoryCard(order: orders[index]),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistoryCard extends StatefulWidget {
  const _OrderHistoryCard({required this.order});

  final TkOrder order;

  @override
  State<_OrderHistoryCard> createState() => _OrderHistoryCardState();
}

class _OrderHistoryCardState extends State<_OrderHistoryCard> {
  bool _repeating = false;
  String? _fetchedImageUrl; // lazily fetched when order has no restaurantImage

  TkOrder get order => widget.order;

  @override
  void initState() {
    super.initState();
    // If the order already has an image, nothing to fetch.
    if (order.restaurantImage.isEmpty && order.restaurantId.isNotEmpty) {
      FirestoreService.restaurantById(order.restaurantId).first
          .then((doc) {
            if (!mounted || !doc.exists) return;
            final data = doc.data() as Map<String, dynamic>? ?? {};
            // Try cover, logo, or location image
            final img = (data['cover'] as String? ?? '').trim().isNotEmpty
                ? data['cover'] as String
                : (data['logo'] as String? ?? '').trim().isNotEmpty
                ? data['logo'] as String
                : '';
            if (img.isNotEmpty) setState(() => _fetchedImageUrl = img);
          })
          .catchError((_) {});
    }
  }

  String get _firstImageUrl {
    // 1. Image stored on the order document (new orders)
    if (order.restaurantImage.isNotEmpty) return order.restaurantImage;
    // 2. Lazily fetched from the restaurant document
    if (_fetchedImageUrl != null && _fetchedImageUrl!.isNotEmpty) {
      return _fetchedImageUrl!;
    }
    // 3. First item image (legacy fallback)
    for (final item in order.items) {
      final img =
          item['image']?.toString() ?? item['imageUrl']?.toString() ?? '';
      if (img.isNotEmpty) return img;
    }
    return '';
  }

  String get _dateLabel {
    final d = order.createdAt;
    if (d == null) return '';
    final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    final months = [
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
    return 'Date : ${months[d.month - 1]} ${d.day},${d.year} At $hour:$minute $amPm';
  }

  Future<void> _repeatOrder(BuildContext context) async {
    if (_repeating) return;
    setState(() => _repeating = true);

    // Capture context-dependent objects before any async gap.
    final cart = CartScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // Fetch live food items for this restaurant.
      final restaurantId = order.restaurantId;
      final QuerySnapshot snap = restaurantId.isNotEmpty
          ? await FirestoreService.foodItemsForRestaurant(restaurantId).first
          : await FirestoreService.foodItemsByRestaurantName(
              order.restaurantName,
            ).first;

      final liveItems = snap.docs.map(FoodItem.fromDoc).toList();

      // Match each ordered item by name (case-insensitive).
      int added = 0;
      int unavailable = 0;
      final List<({FoodItem item, int qty})> toAdd = [];

      for (final orderedItem in order.items) {
        final name = (orderedItem['name'] as String? ?? '')
            .trim()
            .toLowerCase();
        final qty =
            ((orderedItem['qty'] ?? orderedItem['quantity'] ?? 1) as num)
                .toInt();
        if (name.isEmpty) continue;

        final match = liveItems.where(
          (f) =>
              f.name.trim().toLowerCase() == name &&
              f.available &&
              f.inStock &&
              f.status == 'active',
        );

        if (match.isNotEmpty) {
          toAdd.add((item: match.first, qty: qty));
          added++;
        } else {
          unavailable++;
        }
      }

      if (!mounted) return;

      if (toAdd.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              unavailable > 0
                  ? 'None of the items are currently available'
                  : 'No items found for this order',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Clear existing cart items but preserve the delivery address.
      final preservedAddress = cart.selectedAddress;
      cart.clear();
      if (preservedAddress != null) cart.setAddress(preservedAddress);
      for (final entry in toAdd) {
        cart.addItem(item: entry.item, quantity: entry.qty);
      }

      // Show feedback snackbar — items were added directly to cart.
      final msg = unavailable > 0
          ? '$added item${added > 1 ? 's' : ''} added to cart · $unavailable unavailable'
          : '$added item${added > 1 ? 's' : ''} added to cart';
      messenger.showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

      // Navigate to cart summary so user can directly proceed to checkout.
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(builder: (_) => const CartSummaryScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not repeat order. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _repeating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _firstImageUrl;
    final dateLabel = _dateLabel;
    final status = order.status.toLowerCase();
    final isCancelled = status == 'cancelled';
    final isDelivered = status == 'delivered';
    final isActive = !isCancelled && !isDelivered;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top section: image + key info ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Food image thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _PlaceholderThumb(),
                          )
                        : _PlaceholderThumb(),
                  ),
                ),
                const SizedBox(width: 12),
                // Restaurant info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Restaurant name + status badge on same row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              order.restaurantName.isEmpty
                                  ? AppConstants.appName
                                  : order.restaurantName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(status: order.status),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order.address.isEmpty ? '—' : order.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Order ID : ${order.orderNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF444444),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Item Total : ₹${order.subtotal}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF444444),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Payment : ${order.paymentMethod}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF444444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Dotted divider ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _DottedLine(),
          ),

          // ── Detail rows ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dateLabel.isNotEmpty) _DetailRow(dateLabel),
                _DetailRow(
                  'Phone Number : ${order.customerPhone.isEmpty ? '—' : order.customerPhone}',
                ),
                _DetailRow(
                  'Deliver To : ${order.addressLabel.isNotEmpty ? order.addressLabel + ' · ' : ''}${order.address.isEmpty ? '—' : order.address}',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _BillLine('Item Total', '₹${order.subtotal}'),
                      _BillLine('Delivery Fee', '₹${order.deliveryFee}'),
                      if (order.surgeFee > 0)
                        _BillLine(
                          '  ↳ Incl. Surge Fee',
                          '₹${order.surgeFee}',
                          surge: true,
                        ),
                      _BillLine('Platform Fee', '₹${order.platformFee}'),
                      _BillLine('Taxes & GST', '₹${order.tax}'),
                      if (order.discount > 0)
                        _BillLine(
                          'Discount',
                          '- ₹${order.discount}',
                          discount: true,
                        ),
                      if (order.tip > 0)
                        _BillLine('Tip 🙏', '₹${order.tip}', tip: true),
                      // When wallet was applied, order.total is already post-wallet.
                      // Show pre-wallet amount first, then deduct wallet, so the
                      // math is transparent: preWallet - walletUsed = total (amount due).
                      if (order.walletUsed > 0) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(height: 1, color: Color(0xFFE0E0E0)),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '₹${order.total + order.walletUsed}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _BillLine(
                          'Wallet Applied 💙',
                          '- ₹${order.walletUsed}',
                          wallet: true,
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, color: Color(0xFFE0E0E0)),
                      ),
                      Row(
                        children: [
                          Text(
                            // For COD+wallet: clarify how much cash is due
                            order.walletUsed > 0 &&
                                    ['cash', 'cod'].contains(
                                      order.paymentMethod.toLowerCase(),
                                    )
                                ? 'Cash Due'
                                : 'Grand Total',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '₹${order.total}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Action buttons ─────────────────────────────────────
                if (isActive) ...[
                  // Active order: Track Order primary + Repeat Order secondary
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrackOrderScreen(orderId: order.id),
                        ),
                      ),
                      icon: const Icon(Icons.location_on_rounded, size: 18),
                      label: const Text(
                        'Track Order',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _repeating
                          ? null
                          : () => _repeatOrder(context),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: _repeating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Text(
                              'Repeat Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Delivered / Cancelled: show Repeat Order button.
                  // For cancelled orders also show a small status label above it.
                  if (isCancelled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'Order Cancelled',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _repeating
                          ? null
                          : () => _repeatOrder(context),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: _repeating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Text(
                              'Repeat Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(
                          alpha: 0.6,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
  }
}

/// Coloured status pill shown on the top-right of each order card.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  static _BadgeStyle _style(String s) {
    switch (s.toLowerCase()) {
      case 'cancelled':
        return _BadgeStyle(
          bg: const Color(0xFFFFECEC),
          fg: AppColors.primary,
          label: 'Cancelled',
        );
      case 'delivered':
        return _BadgeStyle(
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          label: 'Delivered',
        );
      case 'picked':
      case 'picked_up':
      case 'out_for_delivery':
      case 'on_the_way':
      case 'dispatched':
        return _BadgeStyle(
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
          label: 'On the way',
        );
      case 'preparing':
      case 'ready':
        return _BadgeStyle(
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
          label: 'Preparing',
        );
      case 'accepted':
      case 'confirmed':
        return _BadgeStyle(
          bg: const Color(0xFFEDE7F6),
          fg: const Color(0xFF4527A0),
          label: 'Accepted',
        );
      default: // pending
        return _BadgeStyle(
          bg: const Color(0xFFF5F5F5),
          fg: const Color(0xFF757575),
          label: 'Pending',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: s.fg,
        ),
      ),
    );
  }
}

class _BadgeStyle {
  final Color bg;
  final Color fg;
  final String label;
  const _BadgeStyle({required this.bg, required this.fg, required this.label});
}

/// Single line of detail text inside the card.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.text, {this.maxLines = 1});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          color: Color(0xFF333333),
          height: 1.5,
        ),
      ),
    );
  }
}

/// Placeholder when there's no food image.
class _PlaceholderThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFE8E8),
      child: const Center(
        child: Icon(Icons.fastfood_rounded, color: AppColors.primary, size: 32),
      ),
    );
  }
}

/// Dotted horizontal divider.
class _DottedLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 6.0;
        const dashSpace = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          children: List.generate(count, (_) {
            return Container(
              width: dashWidth,
              height: 1,
              margin: const EdgeInsets.only(right: dashSpace),
              color: const Color(0xFFDDDDDD),
            );
          }),
        );
      },
    );
  }
}

/// Fee-breakdown row inside the order-history card bill box.
class _BillLine extends StatelessWidget {
  const _BillLine(
    this.label,
    this.value, {
    this.discount = false,
    this.tip = false,
    this.surge = false,
    this.wallet = false,
  });

  final String label;
  final String value;
  final bool discount;
  final bool tip;
  final bool surge; // surge sub-row shown in amber/orange
  final bool wallet; // wallet deduction shown in blue/teal

  @override
  Widget build(BuildContext context) {
    final Color labelColor;
    final Color valueColor;

    if (discount || tip) {
      labelColor = const Color(0xFF2E7D32);
      valueColor = const Color(0xFF2E7D32);
    } else if (surge) {
      labelColor = const Color(0xFFE65100);
      valueColor = const Color(0xFFE65100);
    } else if (wallet) {
      labelColor = const Color(0xFF1565C0); // blue — wallet credit
      valueColor = const Color(0xFF1565C0);
    } else {
      labelColor = const Color(0xFF555555);
      valueColor = const Color(0xFF1A1A1A);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: labelColor,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
