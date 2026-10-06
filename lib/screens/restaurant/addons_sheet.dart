import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../models/food_item.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';

class AddonSelectionResult {
  final int quantity;
  final List<CartAddon> addons;
  final String instructions;

  const AddonSelectionResult({
    required this.quantity,
    required this.addons,
    required this.instructions,
  });
}

class AddonsSheet extends StatefulWidget {
  const AddonsSheet({
    super.key,
    required this.item,
    this.restaurantId,
    this.scrollController,
  });

  final FoodItem item;
  final String? restaurantId;
  final ScrollController? scrollController;

  static Future<AddonSelectionResult?> show(
    BuildContext context, {
    required FoodItem item,
    String? restaurantId,
  }) {
    return showModalBottomSheet<AddonSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => AddonsSheet(
          item: item,
          restaurantId: restaurantId,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<AddonsSheet> createState() => _AddonsSheetState();
}

class _AddonsSheetState extends State<AddonsSheet> {
  int _qty = 1;

  // Key is "name|price" so two addons with the same name but different prices
  // are treated as completely independent items (e.g. "Extra Cheese|40" and
  // "Extra Cheese|30" never cross-select each other).
  final Set<String> _selected = {};

  final _instructionsCtrl = TextEditingController();

  static const _fallback = [
    CartAddon(name: 'Extra Cheese', price: 40),
    CartAddon(name: 'Extra Patty', price: 60),
    CartAddon(name: 'Extra Veggies', price: 30),
  ];

  /// Unique key for an addon — combines name + price so duplicates are independent.
  String _key(CartAddon a) => '${a.name}|${a.price}';

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  List<CartAddon> _parseAddons(QuerySnapshot? snap) {
    if (snap == null || snap.docs.isEmpty) return _fallback;
    final rid = widget.restaurantId ?? widget.item.restaurantId;
    final list = snap.docs
        .map(AddonItem.fromDoc)
        .where((a) {
          final active = a.status.isEmpty || a.status == 'active';
          if (!active || a.name.isEmpty) return false;
          if (rid.isEmpty) return true;
          return a.restaurantId == null ||
              a.restaurantId!.isEmpty ||
              a.restaurantId == rid;
        })
        .map((a) => CartAddon(name: a.name, price: a.price))
        .toList();
    return list.isEmpty ? _fallback : list;
  }

  int _total(List<CartAddon> options) {
    final addonTotal = options
        .where((a) => _selected.contains(_key(a)))
        .fold(0, (s, a) => s + a.price);
    return (widget.item.displayPrice + addonTotal) * _qty;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: (widget.restaurantId ?? widget.item.restaurantId).isNotEmpty
            ? FirestoreService.addonsForRestaurant(
                widget.restaurantId ?? widget.item.restaurantId,
              )
            : FirestoreService.allAddons(),
        builder: (context, snapshot) {
          final options = _parseAddons(snapshot.data);
          return SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle bar ────────────────────────────────────────
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
                const SizedBox(height: 12),
                // ── Title row ─────────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      "Add On's",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Veg / non-veg indicator matching the food item
                    _VegIndicator(isVeg: item.isVeg),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Item header ───────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${item.displayPrice}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: item.image.isNotEmpty
                            ? Image.network(item.image, fit: BoxFit.cover)
                            : Container(color: const Color(0xFFEEEEEE)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                // ── Addon checkboxes ──────────────────────────────────
                // Each addon is keyed by "name|price" so two addons that
                // share the same name (e.g. Extra Cheese ₹40 and ₹30) are
                // fully independent and never cross-select each other.
                ...options.map((addon) {
                  final key = _key(addon);
                  final checked = _selected.contains(key);
                  return CheckboxListTile(
                    key: ValueKey(key),
                    value: checked,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.trailing,
                    activeColor: AppColors.primary,
                    title: Text(
                      '${addon.name}  (+₹${addon.price})',
                      style: const TextStyle(fontSize: 14),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(key);
                        } else {
                          _selected.remove(key);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 8),
                // ── Special requirements ──────────────────────────────
                const Text(
                  'Special Requirements',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _instructionsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Add Cooking Instructions Or Special Requirements (E.g No Onion, Separate Pack)',
                    hintStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Quantity + Add Item button ─────────────────────────
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDDDDDD)),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _qty > 1
                                ? () => setState(() => _qty--)
                                : null,
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          Text(
                            '$_qty',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _qty++),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Resolve selected addons back to CartAddon objects
                          // using the same name|price key — never by name alone.
                          final addons = options
                              .where((a) => _selected.contains(_key(a)))
                              .toList();
                          Navigator.pop(
                            context,
                            AddonSelectionResult(
                              quantity: _qty,
                              addons: addons,
                              instructions: _instructionsCtrl.text.trim(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          'Add Item  ₹${_total(options)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Standard FSSAI veg / non-veg square indicator.
/// Veg  → green border + green filled circle
/// Non-veg → red border + red filled upward triangle
class _VegIndicator extends StatelessWidget {
  const _VegIndicator({required this.isVeg});

  final bool isVeg;

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C);

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: isVeg
            ? CircleAvatar(radius: 4, backgroundColor: color)
            : CustomPaint(
                size: const Size(8, 8),
                painter: _TrianglePainter(color: color),
              ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
