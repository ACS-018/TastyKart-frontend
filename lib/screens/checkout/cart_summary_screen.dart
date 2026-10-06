import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../constants/color_constants.dart';
import '../../constants/map_constants.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../services/wallet_service.dart';
import '../../state/cart_controller.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_navigation.dart';
import '../../widgets/app_screen_header.dart';
import '../location/select_location_screen.dart';
import '../restaurant/addons_sheet.dart';
import 'payment_options_screen.dart';

class CartSummaryScreen extends StatefulWidget {
  const CartSummaryScreen({super.key});

  @override
  State<CartSummaryScreen> createState() => _CartSummaryScreenState();
}

class _CartSummaryScreenState extends State<CartSummaryScreen> {
  Restaurant? _restaurant;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cart = CartScope.of(context);
    final restaurantId = cart.lines.isNotEmpty
        ? cart.lines.first.item.restaurantId
        : '';
    if (restaurantId.isNotEmpty && _restaurant == null) {
      FirestoreService.restaurantById(restaurantId).first.then((doc) {
        if (doc.exists && mounted) {
          final r = Restaurant.fromDoc(doc);
          setState(() => _restaurant = r);
          // Store image URL + coordinates on cart so they're written into the order payload.
          // restaurantLat/Lng are required by the admin auto-assignment logic.
          final c = CartScope.of(context);
          c.restaurantImage = r.imageUrl;
          if (r.lat != null) c.restaurantLat = r.lat;
          if (r.lng != null) c.restaurantLng = r.lng;
          if (r.address.isNotEmpty) c.restaurantAddress = r.address;
          c.setSurgeCity(r.city);
          _updateDistance(c, r);
        }
      });
    }
  }

  void _updateDistance(CartController cart, Restaurant restaurant) {
    final addr = cart.selectedAddress;
    if (addr?.lat == null ||
        addr?.lng == null ||
        restaurant.lat == null ||
        restaurant.lng == null) {
      cart.setDistanceKm(null);
      return;
    }
    // Use Google Distance Matrix API (driving) so we get road distance, not
    // straight-line. Falls back to straight-line if the API call fails.
    _fetchRoadDistanceKm(
      originLat: addr!.lat!,
      originLng: addr.lng!,
      destLat: restaurant.lat!,
      destLng: restaurant.lng!,
    ).then((km) {
      if (mounted) cart.setDistanceKm(km);
    });
  }

  /// Calls the Google Maps Distance Matrix API and returns the driving distance
  /// in kilometres. Falls back to straight-line distance if the request fails
  /// or the API returns no result (e.g. no internet, quota exceeded).
  Future<double> _fetchRoadDistanceKm({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
          'origins': '$originLat,$originLng',
          'destinations': '$destLat,$destLng',
          'mode': 'driving',
          'key': MapConstants.googleMapKey,
        });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final rows = json['rows'] as List?;
        if (rows != null && rows.isNotEmpty) {
          final elements = rows[0]['elements'] as List?;
          if (elements != null && elements.isNotEmpty) {
            final element = elements[0] as Map<String, dynamic>;
            if (element['status'] == 'OK') {
              final metres = (element['distance']['value'] as num).toDouble();
              return metres / 1000;
            }
          }
        }
      }
    } catch (_) {
      // Network error, timeout, or JSON parse failure — fall through to
      // straight-line fallback so the fee still shows something reasonable.
    }

    // Straight-line fallback
    final metres = Geolocator.distanceBetween(
      originLat,
      originLng,
      destLat,
      destLng,
    );
    return metres / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    final distKm = cart.distanceKm;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Cart Summary',
            subtitle: 'Your Order Is Here',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: cart.isEmpty
                  ? const Center(child: Text('Your cart is empty'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
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
                            children: [
                              for (var i = 0; i < cart.lines.length; i++) ...[
                                if (i > 0) const Divider(height: 24),
                                _CartLineTile(
                                  line: cart.lines[i],
                                  onMinus: () => cart.updateQuantity(
                                    i,
                                    cart.lines[i].quantity - 1,
                                  ),
                                  onPlus: () => cart.updateQuantity(
                                    i,
                                    cart.lines[i].quantity + 1,
                                  ),
                                  onCustomise: () async {
                                    final item = cart.lines[i].item;
                                    final result = await AddonsSheet.show(
                                      context,
                                      item: item,
                                      restaurantId: item.restaurantId,
                                    );
                                    if (result == null || !context.mounted) {
                                      return;
                                    }
                                    CartScope.of(context).replaceItem(
                                      foodItemId: item.id,
                                      item: item,
                                      quantity: result.quantity,
                                      addons: result.addons,
                                      instructions: result.instructions,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Bill Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _BillRow('Items Total', '₹${cart.itemsMrpTotal}'),
                              // Delivery Fee — expandable breakdown
                              _DeliveryFeeRow(cart: cart, distKm: distKm),
                              _BillRow('Taxes & GST', '₹${cart.taxes}'),
                              if (cart.discount > 0)
                                _BillRow(
                                  'Discount',
                                  '- ₹${cart.discount}',
                                  discountStyle: true,
                                ),
                              if (cart.platformFee > 0)
                                _BillRow(
                                  'Platform Fee',
                                  '₹${cart.platformFee}',
                                ),
                              if (cart.tipAmount > 0)
                                _BillRow('Tip 🙏', '₹${cart.tipAmount}'),
                              // ── Wallet ─────────────────────────────
                              // Always show for signed-in users so the
                              // feature is discoverable even at ₹0.
                              if (FirebaseAuth.instance.currentUser != null)
                                _WalletRow(cart: cart),
                              const Divider(height: 24),
                              _BillRow(
                                'Grand Total',
                                '₹${cart.grandTotal}',
                                bold: true,
                                highlight: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ── Tip for delivery partner ──────────────────
                        _TipSelector(cart: cart),
                        if (cart.selectedAddress != null) ...[
                          const SizedBox(height: 16),
                          _AddressTile(
                            address: cart.selectedAddress!.label,
                            fullAddress: cart.selectedAddress!.fullAddress,
                            onTap: () async {
                              final picked = await SelectLocationScreen.pick(
                                context,
                              );
                              if (picked != null && context.mounted) {
                                cart.setAddress(picked);
                                final r = _restaurant;
                                if (r != null) _updateDistance(cart, r);
                              }
                            },
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          _AddressTile(
                            address: 'No address selected',
                            fullAddress: 'Tap to add a delivery address',
                            isEmpty: true,
                            onTap: () async {
                              final picked = await SelectLocationScreen.pick(
                                context,
                              );
                              if (picked != null && context.mounted) {
                                cart.setAddress(picked);
                                final r = _restaurant;
                                if (r != null) _updateDistance(cart, r);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (!cart.isEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _ProceedButton(cart: cart),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onMinus,
    required this.onPlus,
    required this.onCustomise,
  });

  final CartLine line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onCustomise;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: line.item.image.isNotEmpty
                ? Image.network(line.item.image, fit: BoxFit.cover)
                : Container(color: const Color(0xFFEEEEEE)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.item.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '₹${line.unitTotal}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              if (line.item.hasDiscount) ...[
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      '₹${line.item.price}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Color(0xFF9E9E9E),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${line.item.discountPercent}% off',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (line.addons.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: line.addons
                      .map(
                        (a) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFFCC80)),
                          ),
                          child: Text(
                            '+ ${a.name}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onCustomise,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    line.addons.isEmpty ? '+ Add-ons' : 'Edit Add-ons',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onMinus,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              Text(
                '${line.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onPlus,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProceedButton extends StatefulWidget {
  const _ProceedButton({required this.cart});

  final CartController cart;

  @override
  State<_ProceedButton> createState() => _ProceedButtonState();
}

class _ProceedButtonState extends State<_ProceedButton> {
  bool _loading = false;

  Future<void> _proceed() async {
    if (_loading) return;
    setState(() => _loading = true);
    AppFeedback.light();
    try {
      if (!widget.cart.hasDeliveryAddress) {
        final address = await SelectLocationScreen.pick(context);
        if (address == null || !mounted) return;
        widget.cart.setAddress(address);
      }
      if (!mounted) return;
      await AppNavigation.push(context, const PaymentOptionsScreen());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : _proceed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFD6D6),
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: const Color(0xFFFFE8E8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(
                widget.cart.hasDeliveryAddress
                    ? 'Proceed to Payment'
                    : 'Select Address & Pay At Next Step',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.address,
    required this.fullAddress,
    required this.onTap,
    this.isEmpty = false,
  });

  final String address;
  final String fullAddress;
  final VoidCallback onTap;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEmpty
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isEmpty
                  ? Icons.add_location_alt_rounded
                  : Icons.location_on_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isEmpty
                          ? AppColors.primary
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fullAddress,
                    style: TextStyle(
                      fontSize: 12,
                      color: isEmpty
                          ? AppColors.primary.withValues(alpha: 0.7)
                          : const Color(0xFF6B6B6B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipSelector extends StatelessWidget {
  const _TipSelector({required this.cart});
  final CartController cart;

  static const _tips = [10, 20, 30, 50];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tip your delivery partner 🙏',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '100% goes to your delivery partner',
            style: TextStyle(fontSize: 12, color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: cart,
            builder: (context, _) {
              return Row(
                children: [
                  ..._tips.map((amount) {
                    final selected = cart.tipAmount == amount;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => cart.setTip(selected ? 0 : amount),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 40,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : const Color(0xFFDDDDDD),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '₹$amount',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppColors.white
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  // "None" pill
                  GestureDetector(
                    onTap: () => cart.setTip(0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: cart.tipAmount == 0
                            ? AppColors.primary
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cart.tipAmount == 0
                              ? AppColors.primary
                              : const Color(0xFFDDDDDD),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'None',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cart.tipAmount == 0
                                ? AppColors.white
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Delivery Fee expandable breakdown ────────────────────────────────────────
/// Shows a single "Delivery Fee" row that expands on tap to reveal how the
/// total is built: Base fee  +  Distance component  +  City surge (if any).
/// Subscription free-delivery and threshold-free-delivery are also handled.
class _DeliveryFeeRow extends StatefulWidget {
  const _DeliveryFeeRow({required this.cart, required this.distKm});

  final CartController cart;
  final double? distKm;

  @override
  State<_DeliveryFeeRow> createState() => _DeliveryFeeRowState();
}

class _DeliveryFeeRowState extends State<_DeliveryFeeRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final distKm = widget.distKm;
    final charges = cart.charges;

    // ── Component calculations ───────────────────────────────────────────
    final isFree =
        cart.hasActiveSubscription ||
        (charges.freeDeliveryThreshold > 0 &&
            cart.itemsTotal >= charges.freeDeliveryThreshold);

    // Base flat fee (ignores distance and surge).
    final baseFee = isFree ? 0 : charges.baseDeliveryFee;

    // Distance-based component only.
    final distFee = (distKm != null && distKm > 0 && !isFree)
        ? (charges.perKmRate * distKm).ceil()
        : 0;

    // City surge on top.
    final surge = isFree ? 0 : cart.activeCitySurge;

    // Grand delivery total (already computed by CartController).
    final total = cart.deliveryFee;

    // ── Free-delivery reason label ──────────────────────────────────────
    String? freeReason;
    if (cart.hasActiveSubscription) {
      freeReason = 'Free with your subscription';
    } else if (charges.freeDeliveryThreshold > 0 &&
        cart.itemsTotal >= charges.freeDeliveryThreshold) {
      freeReason = 'Free on orders ₹${charges.freeDeliveryThreshold}+';
    }

    final totalStr = total == 0 ? 'FREE' : '₹$total';
    final headerColor = total == 0
        ? const Color(0xFF2E7D32)
        : const Color(0xFF1A1A1A);
    final headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: headerColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tappable header row ────────────────────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text('Delivery Fee', style: headerStyle),
                  const SizedBox(width: 4),
                  // Chevron rotates when expanded
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: headerColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    totalStr,
                    style: headerStyle.copyWith(color: headerColor),
                  ),
                ],
              ),
            ),
          ),

          // ── Free-delivery subtitle (always visible when free) ──────────
          if (freeReason != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 12,
                  color: Color(0xFF2E7D32),
                ),
                const SizedBox(width: 4),
                Text(
                  '✓ $freeReason',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          // ── Expandable breakdown ───────────────────────────────────────
          FadeTransition(
            opacity: _fade,
            child: SizeTransition(
              sizeFactor: _fade,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  children: [
                    // Base fee row
                    _BreakdownLine(
                      icon: Icons.home_rounded,
                      label: 'Base delivery fee',
                      value: isFree ? '—' : '₹$baseFee',
                    ),

                    // Distance row
                    if (!isFree) ...[
                      const SizedBox(height: 6),
                      _BreakdownLine(
                        icon: Icons.route_rounded,
                        label: distKm != null
                            ? '${distKm.toStringAsFixed(1)} km by road'
                                  ' × ₹${charges.perKmRate}/km'
                            : 'Distance fee (calculating…)',
                        value: distKm != null ? '₹$distFee' : '—',
                        isCalculating: distKm == null,
                      ),
                    ],

                    // Surge row — only shown when active
                    if (surge > 0) ...[
                      const SizedBox(height: 6),
                      _BreakdownLine(
                        icon: Icons.bolt_rounded,
                        label: 'City surge (${cart.surgeCity})',
                        value: '₹$surge',
                        valueColor: const Color(0xFFE65100),
                      ),
                    ],

                    // Subscription saving row
                    if (cart.hasActiveSubscription) ...[
                      const SizedBox(height: 6),
                      _BreakdownLine(
                        icon: Icons.card_membership_rounded,
                        label: 'Subscription saving',
                        value: '- ₹${charges.baseDeliveryFee}',
                        valueColor: const Color(0xFF2E7D32),
                      ),
                    ],

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Color(0xFFDDDDDD)),
                    ),

                    // Total
                    Row(
                      children: [
                        const Text(
                          'Total delivery fee',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          totalStr,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: total == 0
                                ? const Color(0xFF2E7D32)
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single line inside the delivery fee breakdown panel.
class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isCalculating = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isCalculating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
          ),
        ),
        isCalculating
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF9E9E9E),
                ),
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? const Color(0xFF1A1A1A),
                ),
              ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow(
    this.label,
    this.value, {
    this.bold = false,
    this.highlight = false,
    this.discountStyle = false,
    this.freeStyle = false,
    this.subtitle,
  });

  final String label;
  final String value;
  final bool bold;
  final bool highlight;
  final bool discountStyle;
  final bool freeStyle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color = discountStyle || freeStyle
        ? const Color(0xFF2E7D32)
        : highlight
        ? AppColors.primary
        : const Color(0xFF1A1A1A);
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: style),
              const Spacer(),
              Text(value, style: style),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.social_distance_rounded,
                  size: 12,
                  color: Color(0xFF9E9E9E),
                ),
                const SizedBox(width: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bill row that shows wallet balance and opens a custom-amount sheet.
/// Bill row — StatefulWidget so it holds its own Firestore subscription
/// and doesn't lose the balance on parent rebuilds.
class _WalletRow extends StatefulWidget {
  const _WalletRow({required this.cart});
  final CartController cart;

  @override
  State<_WalletRow> createState() => _WalletRowState();
}

class _WalletRowState extends State<_WalletRow> {
  int _balance = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Seed immediately from cart (populated by auth_gate stream).
    _balance = widget.cart.walletBalance;
    if (_balance > 0) _loaded = true;
    // Always fire a direct fetch so we're not dependent on auth_gate timing.
    _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final bal = await WalletService.fetchBalance(uid);
      if (!mounted) return;
      if (bal != widget.cart.walletBalance) {
        widget.cart.setWalletBalance(bal);
      }
      setState(() {
        _balance = bal;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WalletAmountSheet(cart: widget.cart, balance: _balance),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cart,
      builder: (context, _) {
        // Use whichever is fresher: our fetched value or what auth_gate pushed.
        final balance = widget.cart.walletBalance > _balance
            ? widget.cart.walletBalance
            : _balance;
        final applied = widget.cart.walletApplied;
        final hasBalance = balance > 0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 15,
                color: hasBalance
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loaded
                          ? 'Wallet Balance  ₹$balance'
                          : 'Wallet Balance  …',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: hasBalance
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF9E9E9E),
                      ),
                    ),
                    if (applied > 0)
                      Text(
                        '- ₹$applied applied',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2E7D32),
                        ),
                      )
                    else if (_loaded && !hasBalance)
                      const Text(
                        'No wallet balance available',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Right-side actions ─────────────────────────────
              if (!_loaded)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2E7D32),
                  ),
                )
              else if (applied > 0) ...[
                GestureDetector(
                  onTap: _openSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      '- ₹$applied  ✎',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => widget.cart.setWalletApplied(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDDDDDD)),
                    ),
                    child: const Text(
                      'Remove',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ),
                ),
              ] else if (hasBalance)
                GestureDetector(
                  onTap: _openSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDDDDDD)),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333),
                      ),
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

// ── Custom wallet amount bottom sheet ─────────────────────────────────────────

class _WalletAmountSheet extends StatefulWidget {
  const _WalletAmountSheet({required this.cart, required this.balance});

  final CartController cart;
  final int balance;

  @override
  State<_WalletAmountSheet> createState() => _WalletAmountSheetState();
}

class _WalletAmountSheetState extends State<_WalletAmountSheet> {
  late final TextEditingController _ctrl;
  String? _error;

  // Max the user can apply = min(balance, pre-wallet order total)
  int get _maxApplicable {
    final preWallet =
        widget.cart.itemsMrpTotal +
        widget.cart.deliveryFee +
        widget.cart.taxes +
        widget.cart.platformFee -
        widget.cart.discount +
        widget.cart.tipAmount;
    return widget.balance.clamp(0, preWallet);
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill only when editing an already-applied amount.
    // For first open, leave blank so the user types their own amount.
    final current = widget.cart.walletApplied;
    _ctrl = TextEditingController(text: current > 0 ? '$current' : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final raw = int.tryParse(_ctrl.text.trim());
    if (raw == null || raw <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (raw > _maxApplicable) {
      setState(() => _error = 'Max you can apply is ₹$_maxApplicable');
      return;
    }
    widget.cart.setWalletApplied(raw);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // padding bottom = keyboard height so the field stays visible
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use Wallet Balance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Available: ₹${widget.balance}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Amount input
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              labelText: 'Amount to apply',
              prefixText: '₹  ',
              hintText: 'e.g. 20',
              border: const OutlineInputBorder(),
              errorText: _error,
              helperText:
                  'Available: ₹${widget.balance}  ·  Max: ₹$_maxApplicable',
              helperStyle: const TextStyle(
                fontSize: 11,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Apply button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
