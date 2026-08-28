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
  });

  final FoodItem item;
  final String? restaurantId;

  static Future<AddonSelectionResult?> show(
    BuildContext context, {
    required FoodItem item,
    String? restaurantId,
  }) {
    return showModalBottomSheet<AddonSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddonsSheet(
        item: item,
        restaurantId: restaurantId,
      ),
    );
  }

  @override
  State<AddonsSheet> createState() => _AddonsSheetState();
}

class _AddonsSheetState extends State<AddonsSheet> {
  int _qty = 1;
  final Set<String> _selected = {};
  final _instructionsCtrl = TextEditingController();

  static const _fallback = [
    CartAddon(name: 'Extra Cheese', price: 40),
    CartAddon(name: 'Extra Patty', price: 60),
    CartAddon(name: 'Extra Veggies', price: 30),
  ];

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  List<CartAddon> _parseAddons(QuerySnapshot? snap) {
    if (snap == null || snap.docs.isEmpty) return _fallback;
    final rid = widget.restaurantId ?? widget.item.restaurantId;
    var list = snap.docs.map(AddonItem.fromDoc).where((a) {
      final active = a.status.isEmpty || a.status == 'active';
      if (!active || a.name.isEmpty) return false;
      if (rid.isEmpty) return true;
      return a.restaurantId == null ||
          a.restaurantId!.isEmpty ||
          a.restaurantId == rid;
    }).map((a) => CartAddon(name: a.name, price: a.price)).toList();
    return list.isEmpty ? _fallback : list;
  }

  int _total(List<CartAddon> options) {
    final addons = options
        .where((a) => _selected.contains(a.name))
        .fold(0, (s, a) => s + a.price);
    return (widget.item.displayPrice + addons) * _qty;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: StreamBuilder<QuerySnapshot>(
            stream: (widget.restaurantId ?? widget.item.restaurantId).isNotEmpty
                ? FirestoreService.addonsForRestaurant(
                    widget.restaurantId ?? widget.item.restaurantId,
                  )
                : FirestoreService.allAddons(),
            builder: (context, snapshot) {
              final options = _parseAddons(snapshot.data);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    Row(
                      children: [
                        const Text(
                          "Add On's",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
                    ...options.map((addon) {
                      final checked = _selected.contains(addon.name);
                      return CheckboxListTile(
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
                              _selected.add(addon.name);
                            } else {
                              _selected.remove(addon.name);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    const Text(
                      'Special Requirements',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
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
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: const Color(0xFFDDDDDD)),
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
                              final addons = options
                                  .where((a) => _selected.contains(a.name))
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
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
        ),
      ),
    );
  }
}
