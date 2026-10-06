import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../../state/diet_filter_controller.dart';
import '../../state/favorites_controller.dart';
import '../../utils/app_feedback.dart';
import '../checkout/cart_summary_screen.dart';
import '../location/select_location_screen.dart';
import 'addons_sheet.dart';

// ── Offer model from Firestore `offers` collection ────────────────────────────

class _RestaurantOffer {
  final String id;
  final String type; // 'percentage' | 'fixed'
  final double discount; // % value or ₹ amount
  final List<String>
  categoryIds; // empty = all categories (when foodItemIds empty)
  final List<String> foodItemIds; // when non-empty, only these menu items
  final DateTime? validTill;

  const _RestaurantOffer({
    required this.id,
    required this.type,
    required this.discount,
    required this.categoryIds,
    required this.foodItemIds,
    this.validTill,
  });

  factory _RestaurantOffer.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final expStr = (d['validTill'] ?? d['expiry'] ?? '') as String;
    DateTime? exp;
    if (expStr.isNotEmpty) {
      try {
        exp = DateTime.parse(expStr);
      } catch (_) {}
    }
    final rawCatIds = d['categoryIds'];
    final catIds = rawCatIds is List
        ? rawCatIds.map((e) => e.toString()).toList()
        : <String>[];
    final rawItemIds = d['foodItemIds'];
    final itemIds = rawItemIds is List
        ? rawItemIds.map((e) => e.toString()).toList()
        : <String>[];
    return _RestaurantOffer(
      id: doc.id,
      type: (d['type'] as String? ?? 'percentage').toLowerCase(),
      discount: (d['discount'] as num? ?? 0).toDouble(),
      categoryIds: catIds,
      foodItemIds: itemIds,
      validTill: exp,
    );
  }

  /// Offer has not passed its expiry date.
  bool get isNotExpired {
    if (validTill == null) return true;
    // Valid through the end of the expiry day.
    final endOfDay = DateTime(
      validTill!.year,
      validTill!.month,
      validTill!.day,
      23,
      59,
      59,
    );
    return !DateTime.now().isAfter(endOfDay);
  }

  /// Returns true when this offer applies to [item] (by item id or category).
  bool appliesTo(FoodItem item) {
    if (foodItemIds.isNotEmpty) {
      return foodItemIds.contains(item.id);
    }
    if (categoryIds.isEmpty) return true; // all menu items
    return categoryIds.contains(item.categoryId) ||
        categoryIds.any(
          (id) => id.toLowerCase() == item.categoryName.toLowerCase(),
        );
  }

  /// Effective unit price after this offer.
  ///
  /// The offer is applied to the item's original [FoodItem.price], never to
  /// an existing menu discount.
  int effectivePrice(FoodItem item) {
    final base = item.price.toDouble();
    final discounted = type == 'percentage'
        ? base * (1 - discount / 100)
        : base - discount;
    return discounted.round().clamp(0, item.price);
  }
}

class RestaurantMenuScreen extends StatefulWidget {
  RestaurantMenuScreen({
    super.key,
    this.restaurant,
    this.restaurantId,
    this.restaurantName,
    this.highlightItem,
  }) : assert(
         restaurant != null ||
             (restaurantId != null && restaurantId.isNotEmpty) ||
             (restaurantName != null && restaurantName.isNotEmpty),
       );

  final Restaurant? restaurant;
  final String? restaurantId;
  final String? restaurantName;
  final FoodItem? highlightItem;

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  // null  = no explicit local filter set yet (global diet mode is used as
  //         the initial default — see _effectiveFilter below).
  // 'veg' | 'nonveg' | 'top' = user made an explicit selection inside the screen.
  String? _filter;

  // Stores both the Firestore doc ID and human name of the selected category.
  // This lets the filter match food items regardless of whether they stored
  // the category as an ID (e.g. "cat_res_1_starters") or a name ("Starters").
  String? _selectedCategoryId; // Firestore doc ID
  String? _selectedCategoryName; // Human-readable name (e.g. "Starters")

  @override
  void initState() {
    super.initState();
    // Initialize filter based on global diet mode from home screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final diet = DietFilterScope.maybeOf(context);
      if (diet != null) {
        setState(() {
          _filter = diet.isVegMode ? 'veg' : 'nonveg';
        });
      }
    });
  }

  /// Returns the active filter string to pass down to _MenuBody.
  ///
  /// The global veg/non-veg toggle has no effect inside the restaurant screen
  /// — all items are shown by default. The local chips (Veg / Non Veg / Top
  /// Rated) are the only way to narrow the list here.
  String? get _effectiveFilter => _filter;

  String get _resolvedId =>
      widget.restaurant?.id ??
      widget.restaurantId ??
      widget.highlightItem?.restaurantId ??
      '';

  String get _resolvedName =>
      widget.restaurant?.name ??
      widget.restaurantName ??
      widget.highlightItem?.restaurantName ??
      'Restaurant';

  /// Directly add item to cart (qty 1, no addons).
  /// Shows address prompt if needed. Stepper appears immediately after.
  Future<void> _addToCart(FoodItem item) async {
    final cart = CartScope.of(context);
    if (!cart.hasDeliveryAddress) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add delivery address'),
          content: const Text(
            'Please add or select a delivery address before adding items to cart.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add address'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        final address = await SelectLocationScreen.pick(context);
        if (address != null && mounted) {
          cart.setAddress(address);
        }
      }
      if (!cart.hasDeliveryAddress || !mounted) return;
    }

    final result = cart.tryAddItem(item: item, quantity: 1);

    if (result == AddToCartResult.noAddress && mounted) {
      AppFeedback.showSnackBar(
        context,
        message: 'Select a delivery address to add items',
      );
      return;
    }

    if (result == AddToCartResult.differentRestaurant && mounted) {
      await _showClearCartDialog(item: item, cart: cart);
    }
  }

  /// Shows a dialog asking the user if they want to clear the existing cart
  /// (from a different restaurant) and start fresh with [item].
  Future<void> _showClearCartDialog({
    required FoodItem item,
    required CartController cart,
  }) async {
    final existingName = cart.currentRestaurantName;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Start new cart?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Your cart has items from $existingName. '
          'Adding items from ${item.restaurantName} will clear your current cart.\n\n'
          'Do you want to start a new cart?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep current cart'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB32B2C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, clear cart'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      cart.clearAndAdd(item: item, quantity: 1);
      AppFeedback.showSnackBar(
        context,
        message: 'Cart updated — now ordering from ${item.restaurantName}',
      );
    }
  }

  /// Open addons sheet so the user can customise an existing cart item.
  Future<void> _openAddons(FoodItem item) async {
    final cart = CartScope.of(context);
    if (!cart.hasDeliveryAddress) return;

    final result = await AddonsSheet.show(
      context,
      item: item,
      restaurantId: _resolvedId.isNotEmpty ? _resolvedId : item.restaurantId,
    );
    if (result == null || !mounted) return;

    // Replace all lines for this item with a fresh customised one.
    cart.replaceItem(
      foodItemId: item.id,
      item: item,
      quantity: result.quantity,
      addons: result.addons,
      instructions: result.instructions,
    );
    if (mounted) {
      AppFeedback.showSuccess(context, '${item.name} updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _resolvedId;
    final effectiveFilter = _effectiveFilter;

    // Prefer live restaurant doc when we have an id.
    if (id.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirestoreService.restaurantById(id),
        builder: (context, restSnap) {
          Restaurant? live;
          if (restSnap.hasData && restSnap.data!.exists) {
            live = Restaurant.fromDoc(restSnap.data!);
          }
          final restaurant = live ?? widget.restaurant;
          return _MenuBody(
            restaurant: restaurant,
            restaurantId: id,
            restaurantName: restaurant?.name ?? _resolvedName,
            filter: effectiveFilter,
            selectedCategoryId: _selectedCategoryId,
            selectedCategoryName: _selectedCategoryName,
            onFilter: (v) => setState(() => _filter = _filter == v ? '' : v),
            onCategory: (cid, cname) => setState(() {
              // Toggle off if already selected, otherwise store both id and name.
              if (_selectedCategoryId == cid) {
                _selectedCategoryId = null;
                _selectedCategoryName = null;
              } else {
                _selectedCategoryId = cid;
                _selectedCategoryName = cname;
              }
            }),
            onAdd: _addToCart,
            onCustomise: _openAddons,
          );
        },
      );
    }

    return _MenuBody(
      restaurant: widget.restaurant,
      restaurantId: '',
      restaurantName: _resolvedName,
      filter: effectiveFilter,
      selectedCategoryId: _selectedCategoryId,
      selectedCategoryName: _selectedCategoryName,
      onFilter: (v) => setState(() => _filter = _filter == v ? '' : v),
      onCategory: (cid, cname) => setState(() {
        if (_selectedCategoryId == cid) {
          _selectedCategoryId = null;
          _selectedCategoryName = null;
        } else {
          _selectedCategoryId = cid;
          _selectedCategoryName = cname;
        }
      }),
      onAdd: _addToCart,
      onCustomise: _openAddons,
    );
  }
}

class _MenuBody extends StatelessWidget {
  const _MenuBody({
    required this.restaurant,
    required this.restaurantId,
    required this.restaurantName,
    required this.filter,
    required this.selectedCategoryId,
    required this.selectedCategoryName,
    required this.onFilter,
    required this.onCategory,
    required this.onAdd,
    required this.onCustomise,
  });

  final Restaurant? restaurant;
  final String restaurantId;
  final String restaurantName;
  final String? filter;
  final String? selectedCategoryId;
  // The human name matching the selected doc ID — used so the filter catches
  // items that stored categoryName instead of categoryId, and vice versa.
  final String? selectedCategoryName;
  final ValueChanged<String> onFilter;
  // Now receives (docId, humanName) so the parent can store both.
  final void Function(String id, String name) onCategory;
  // Called with a price-adjusted copy of the item so the offer price lands
  // in the cart when the user taps "+ Add".
  final Future<void> Function(FoodItem) onAdd;
  // Same — receives the price-adjusted copy so customise/addons also reflect
  // the offer price.
  final Future<void> Function(FoodItem) onCustomise;

  Stream<QuerySnapshot> get _itemsStream {
    if (restaurantId.isNotEmpty) {
      return FirestoreService.foodItemsForRestaurant(restaurantId);
    }
    return FirestoreService.foodItemsByRestaurantName(restaurantName);
  }

  Stream<QuerySnapshot> get _offersStream {
    if (restaurantId.isNotEmpty) {
      return FirestoreService.offersForRestaurant(restaurantId);
    }
    return const Stream.empty();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        top: false,
        bottom: false,
        child: ColoredBox(
          color: AppColors.primary,
          child: SafeArea(
            top: true,
            bottom: false,
            child: ColoredBox(
              color: AppColors.white,
              child: StreamBuilder<QuerySnapshot>(
                stream: _offersStream,
                builder: (context, offersSnap) {
                  final activeOffers = (offersSnap.data?.docs ?? [])
                      .map(_RestaurantOffer.fromDoc)
                      .where((o) => o.isNotExpired)
                      .toList();

                  return StreamBuilder<QuerySnapshot>(
                    stream: _itemsStream,
                    builder: (context, itemsSnap) {
                      if (itemsSnap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var items = (itemsSnap.data?.docs ?? [])
                          .map(FoodItem.fromDoc)
                          .where((f) {
                            final active =
                                f.status.isEmpty || f.status == 'active';
                            return f.name.isNotEmpty && active;
                          })
                          .toList();

                      // Name fallback if restaurantId query returned empty (legacy docs)
                      if (items.isEmpty && restaurantId.isNotEmpty) {
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirestoreService.foodItemsByRestaurantName(
                            restaurantName,
                          ),
                          builder: (context, nameSnap) {
                            final byName = (nameSnap.data?.docs ?? [])
                                .map(FoodItem.fromDoc)
                                .where((f) => f.name.isNotEmpty)
                                .toList();
                            return _buildContent(context, byName, activeOffers);
                          },
                        );
                      }

                      return _buildContent(context, items, activeOffers);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<FoodItem> rawItems,
    List<_RestaurantOffer> activeOffers,
  ) {
    var items = List<FoodItem>.from(rawItems);

    // NOTE: The global diet filter is intentionally NOT applied here.
    // Instead, _RestaurantMenuScreenState._effectiveFilter() initialises the
    // local filter chip from the global toggle when no explicit selection has
    // been made. This lets users override it (e.g. tap "Non Veg" even when
    // the global toggle is Veg) without getting an empty list.

    if (filter == 'veg') {
      items = items.where((f) => f.isVeg).toList();
    } else if (filter == 'nonveg') {
      items = items.where((f) => !f.isVeg).toList();
    } else if (filter == 'top') {
      items = items.where((f) => f.rating >= 4.0).toList();
    }

    if (selectedCategoryId != null) {
      // Normalise to lower-case trimmed strings so casing/whitespace mismatches
      // (e.g. "Starter" vs "starter", "Starters ") never cause empty results.
      final selId = selectedCategoryId!.trim().toLowerCase();
      final selName = (selectedCategoryName ?? '').trim().toLowerCase();

      debugPrint('[MenuFilter] selId=$selId  selName=$selName');
      debugPrint('[MenuFilter] items before filter: ${rawItems.length}');
      for (final f in rawItems) {
        debugPrint(
          '  item="${f.name}" '
          'catId="${f.categoryId}" catName="${f.categoryName}"',
        );
      }

      items = items.where((f) {
        final fCatId = f.categoryId.trim().toLowerCase();
        final fCatName = f.categoryName.trim().toLowerCase();
        return fCatId == selId ||
            fCatName == selId ||
            (selName.isNotEmpty && fCatId == selName) ||
            (selName.isNotEmpty && fCatName == selName);
      }).toList();

      debugPrint('[MenuFilter] items after filter: ${items.length}');
    }

    // Use dynamic averageRating from the live restaurant doc (written by user
    // reviews via FirestoreService.submitRestaurantRating). Falls back to 0.0
    // when the restaurant doc hasn't loaded yet — never average food-item
    // ratings as that gave a misleading per-page score.
    final rating = restaurant?.rating ?? 0.0;
    final totalReviews = restaurant?.totalReviews ?? 0;
    final delivery = restaurant?.deliveryTime ?? '30 - 40 Min';
    final cuisine = restaurant?.cuisine.isNotEmpty == true
        ? restaurant!.cuisine
        : items
              .map((e) => e.categoryName)
              .where((e) => e.isNotEmpty)
              .toSet()
              .take(4)
              .join(', ');
    final location = restaurant?.locationLabel.isNotEmpty == true
        ? restaurant!.locationLabel
        : (CartScope.maybeOf(context)?.selectedAddress?.label ?? 'Delivery');

    return SafeArea(
      top: false,
      bottom: false,
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Top action bar ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      _CircleIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _CircleIconButton(
                        icon: Icons.share_outlined,
                        onTap: () => _shareRestaurant(context),
                      ),
                      const SizedBox(width: 8),
                      _FavCircleButton(restaurant: restaurant),
                    ],
                  ),
                ),
              ),

              // ── Restaurant info card (Figma style) ─────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEEEE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF5C6C6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              restaurantName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: Color(0xFFFFD700),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  rating > 0
                                      ? rating.toStringAsFixed(1)
                                      : 'New',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                if (totalReviews > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '($totalReviews)',
                                    style: const TextStyle(
                                      color: Color(0xFFFFEBEB),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        restaurant?.description?.isNotEmpty == true
                            ? restaurant!.description!
                            : 'Your Foods Are Here',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$delivery . $location',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4A4A4A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cuisine.isEmpty ? 'Multi Cuisine' : cuisine,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Dotted separator inside the card
                      const _DottedDivider(),
                      const SizedBox(height: 10),
                      // Free delivery — live from Firestore settings
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirestoreService.adminSettings(),
                        builder: (context, snap) {
                          final charges = PlatformCharges.fromSettingsDoc(
                            snap.data,
                          );
                          final threshold = charges.freeDeliveryThreshold;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Free Delivery On ₹$threshold Above',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                      // ── Active offer banner ─────────────────────────────
                      // Shows a scrollable row of offer pills when the admin
                      // has assigned active, non-expired offers to this
                      // restaurant. Hidden automatically when there are none.
                      if (activeOffers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OfferBannerStrip(offers: activeOffers),
                        )
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // ── Filter chips ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                  child: _MenuFilters(selected: filter, onChanged: onFilter),
                ),
              ),

              // ── Food category chips from Firestore ─────────────────────
              if (restaurantId.isNotEmpty)
                SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirestoreService.foodCategoriesForRestaurant(
                      restaurantId,
                    ),
                    builder: (context, catSnap) {
                      final cats =
                          (catSnap.data?.docs ?? [])
                              .map(FoodCategory.fromDoc)
                              .where(
                                (c) =>
                                    c.name.isNotEmpty &&
                                    (c.status.isEmpty || c.status == 'active'),
                              )
                              .toList()
                            ..sort(
                              (a, b) => a.sortOrder.compareTo(b.sortOrder),
                            );

                      debugPrint(
                        '[CategoryChips] count=${cats.length}  '
                        'restaurantId=$restaurantId',
                      );
                      for (final c in cats) {
                        debugPrint(
                          '  cat: id="${c.id}" name="${c.name}" '
                          'status="${c.status}"',
                        );
                      }

                      if (cats.isEmpty) {
                        // Derive from items if admin categories not yet seeded.
                        // In this fallback path there are no doc IDs, so we
                        // pass the name as both id and name — the filter
                        // matches f.categoryName == name correctly.
                        final names = rawItems
                            .map((e) => e.categoryName)
                            .where((e) => e.isNotEmpty)
                            .toSet()
                            .toList();
                        if (names.isEmpty) return const SizedBox.shrink();
                        return _CategoryChips(
                          labels: names,
                          selected: selectedCategoryId,
                          onTap: (name) => onCategory(name, name),
                        );
                      }

                      return SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: cats.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final c = cats[i];
                            final on =
                                selectedCategoryId == c.id ||
                                selectedCategoryId == c.name;
                            return GestureDetector(
                              // Pass both the Firestore doc ID and the human
                              // name so the filter can match items regardless
                              // of which field they stored.
                              onTap: () => onCategory(c.id, c.name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: on
                                      ? AppColors.primary
                                      : AppColors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: on
                                        ? AppColors.primary
                                        : const Color(0xFFDDDDDD),
                                  ),
                                ),
                                child: Text(
                                  c.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: on
                                        ? AppColors.white
                                        : const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),

              // ── Menu items ─────────────────────────────────────────────
              if (items.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('No menu items for this restaurant'),
                  ),
                )
              else
                // Bottom padding adapts to whether the view-cart bar is shown.
                // Use a SliverLayoutBuilder-free approach: always use the
                // larger padding; the ListenableBuilder below handles the bar.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: _DottedDivider(),
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      // Find the first active, non-expired offer that applies
                      // to this item's category.
                      _RestaurantOffer? matchedOffer;
                      for (final o in activeOffers) {
                        if (o.appliesTo(item)) {
                          matchedOffer = o;
                          break;
                        }
                      }
                      final offerPrice = matchedOffer?.effectivePrice(item);
                      String? offerLabel;
                      if (matchedOffer != null) {
                        offerLabel = matchedOffer.type == 'percentage'
                            ? '${matchedOffer.discount.round()}% OFF'
                            : '₹${matchedOffer.discount.round()} OFF';
                      }
                      // Build a price-adjusted copy so the offer price is
                      // what lands in the cart — not just a display override.
                      final cartItem = offerPrice != null
                          ? item.withOfferPrice(offerPrice)
                          : item;
                      return _MenuItemTile(
                        item: item,
                        offerPrice: offerPrice,
                        offerLabel: offerLabel,
                        onAdd: () => onAdd(cartItem),
                        onIncrement: () =>
                            CartScope.of(context).incrementItem(item.id),
                        onDecrement: () =>
                            CartScope.of(context).decrementItem(item.id),
                        onCustomise: () => onCustomise(cartItem),
                      );
                    },
                  ),
                ),
            ],
          ),

          // ── Menu jump FAB — position reacts to cart state only ─────────
          ListenableBuilder(
            listenable: CartScope.of(context),
            builder: (context, _) {
              final cart = CartScope.of(context);
              return Positioned(
                right: 16,
                bottom: cart.isEmpty ? 24 : 88,
                child: FloatingActionButton.extended(
                  onPressed: () => _showMenuJump(context, rawItems),
                  backgroundColor: const Color(0xFF1A1A1A),
                  icon: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Menu',
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),

          // ── View cart bar — only this rebuilds on cart changes ─────────
          ListenableBuilder(
            listenable: CartScope.of(context),
            builder: (context, _) {
              final cart = CartScope.of(context);
              if (cart.isEmpty) return const SizedBox.shrink();
              return Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: SafeArea(
                  top: false,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.primary,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CartSummaryScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${cart.itemCount} Item${cart.itemCount > 1 ? 's' : ''}  |  ₹${cart.itemsTotal}',
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'View Cart',
                              style: TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Share restaurant info + Play Store link via the system share sheet.
  void _shareRestaurant(BuildContext context) {
    final name = restaurant?.name ?? restaurantName;
    final cuisine = restaurant?.cuisine.isNotEmpty == true
        ? restaurant!.cuisine
        : '';
    final rating = restaurant?.rating ?? 0.0;
    const storeUrl =
        'https://play.google.com/store/apps/details?id=com.arrowcoders.foodapp&hl=en';

    final buffer = StringBuffer();
    buffer.writeln('🍽️ $name');
    if (cuisine.isNotEmpty) buffer.writeln('🍴 $cuisine');
    if (rating > 0) buffer.writeln('⭐ ${rating.toStringAsFixed(1)} rating');
    buffer.writeln();
    buffer.writeln('Order now on TastyKart 👇');
    buffer.writeln(storeUrl);

    SharePlus.instance.share(ShareParams(text: buffer.toString().trim()));
  }

  /// Menu jump sheet — loads actual Firestore categories for this restaurant.
  /// Menu jump sheet — loads actual Firestore categories for this restaurant.
  /// [allItems] is the UNFILTERED list so counts always reflect total items
  /// per category regardless of the current veg/nonveg chip selection.
  void _showMenuJump(BuildContext context, List<FoodItem> allItems) {
    if (restaurantId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.foodCategoriesForRestaurant(restaurantId),
        builder: (context, catSnap) {
          final cats =
              (catSnap.data?.docs ?? [])
                  .map(FoodCategory.fromDoc)
                  .where(
                    (c) =>
                        c.name.isNotEmpty &&
                        (c.status.isEmpty || c.status == 'active'),
                  )
                  .toList()
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          /// Count items in a category from the full unfiltered list,
          /// optionally filtering by veg/nonveg.
          int countItems(String catId, String catName, {bool? isVeg}) {
            final id = catId.trim().toLowerCase();
            final name = catName.trim().toLowerCase();
            return allItems.where((f) {
              final fId = f.categoryId.trim().toLowerCase();
              final fName = f.categoryName.trim().toLowerCase();
              final catMatch =
                  fId == id || fName == id || fId == name || fName == name;
              if (!catMatch) return false;
              if (isVeg != null) return f.isVeg == isVeg;
              return true;
            }).length;
          }

          // Fall back to item-derived categories if Firestore returns none.
          final entries = cats.isNotEmpty
              ? cats
                    .map(
                      (c) => (
                        id: c.id,
                        name: c.name,
                        total: countItems(c.id, c.name),
                        veg: countItems(c.id, c.name, isVeg: true),
                        nonVeg: countItems(c.id, c.name, isVeg: false),
                      ),
                    )
                    .toList()
              : <({String id, String name, int total, int veg, int nonVeg})>[];

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
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
                  const SizedBox(height: 14),
                  const Text(
                    'Menu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (catSnap.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No categories available'),
                    )
                  else
                    ...entries.map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: e.total > 0
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (e.veg > 0)
                                    _CountBadge(
                                      count: e.veg,
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  if (e.veg > 0 && e.nonVeg > 0)
                                    const SizedBox(width: 4),
                                  if (e.nonVeg > 0)
                                    _CountBadge(
                                      count: e.nonVeg,
                                      color: const Color(0xFFB71C1C),
                                    ),
                                ],
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          onCategory(e.id, e.name);
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small coloured count badge used in the menu jump sheet.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Offer banner strip ────────────────────────────────────────────────────────
/// Horizontally-scrollable row of offer pills shown in the restaurant info
/// card when there is at least one active, non-expired offer assigned by admin.
class _OfferBannerStrip extends StatelessWidget {
  const _OfferBannerStrip({required this.offers});

  final List<_RestaurantOffer> offers;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // No extra horizontal padding — it sits inside the card padding.
        padding: EdgeInsets.zero,
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = offers[i];
          final label = o.type == 'percentage'
              ? '🏷️ ${o.discount.round()}% OFF'
              : '🏷️ ₹${o.discount.round()} OFF';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF81C784)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2E7D32),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Circular icon button matching the Figma back/share/fav style.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.white,
          border: Border.all(color: const Color(0xFFDDDDDD)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
      ),
    );
  }
}

/// Circular favourite button with same pill shape as Figma header icons.
class _FavCircleButton extends StatelessWidget {
  const _FavCircleButton({required this.restaurant});

  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    if (restaurant == null || restaurant!.id.isEmpty) {
      return const SizedBox.shrink();
    }
    final favorites = FavoritesScope.maybeOf(context);
    if (favorites == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final isOn = favorites.isFavorite(restaurant!.id);
        return GestureDetector(
          onTap: () async {
            AppFeedback.light();
            try {
              await favorites.toggle(restaurant!);
            } catch (_) {
              if (context.mounted) {
                AppFeedback.showError(context, 'Could not update favourites');
              }
            }
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.white,
              border: Border.all(color: const Color(0xFFDDDDDD)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isOn ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(isOn),
                size: 18,
                color: isOn ? AppColors.primary : const Color(0xFF1A1A1A),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  final List<String> labels;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = selected == labels[i];
          return GestureDetector(
            onTap: () => onTap(labels[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: on ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: on ? AppColors.primary : const Color(0xFFDDDDDD),
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuFilters extends StatelessWidget {
  const _MenuFilters({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('veg', 'Veg', const Color(0xFF2E7D32), true),
      ('nonveg', 'Non Veg', const Color(0xFFB71C1C), true),
      ('top', 'Top Rated', const Color(0xFFFFB300), false),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = chips[i].$1;
          final label = chips[i].$2;
          final color = chips[i].$3;
          final isDot = chips[i].$4;
          final isOn = selected == id;
          return GestureDetector(
            onTap: () => onChanged(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                // Selected: white background with a primary-coloured border.
                // Unselected: white background with a light grey border.
                color: AppColors.white,
                borderRadius: BorderRadius.circular(
                  20,
                ), // pill shape — matches Figma
                border: Border.all(
                  color: isOn ? AppColors.primary : const Color(0xFFDDDDDD),
                  width: isOn ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDot)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Always keep the dot's own colour — never turn it white.
                        color: color,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        // Always keep the star's own colour — never turn it white.
                        color: color,
                      ),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      // Text turns primary-red when selected, dark otherwise.
                      color: isOn ? AppColors.primary : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  static const double _height = 1;
  static const Color _color = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final count = (width / (dashWidth + dashSpace)).floor();
        return Row(
          children: List.generate(count, (_) {
            return Container(
              width: dashWidth,
              height: _DottedDivider._height,
              color: _DottedDivider._color,
              margin: const EdgeInsets.only(right: dashSpace),
            );
          }),
        );
      },
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.item,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onCustomise,
    this.offerPrice,
    this.offerLabel,
  });

  final FoodItem item;
  final VoidCallback onAdd;

  /// Directly increments the cart count (no addons sheet).
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Opens the addons/customise sheet for an already-in-cart item.
  final VoidCallback onCustomise;

  /// When non-null, overrides item.displayPrice with this offer price.
  final int? offerPrice;

  /// Short label shown as a badge (e.g. "20% OFF").
  final String? offerLabel;

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final count = cart.countOf(item.id);
        return _buildTile(context, count);
      },
    );
  }

  Widget _buildTile(BuildContext context, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: item.isVeg
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFB71C1C),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: item.isVeg
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFB71C1C),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (item.categoryName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.categoryName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                item.description.isEmpty
                    ? 'Delicious freshly prepared dish from our kitchen.'
                    : item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B6B6B),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // ── Offer badge ───────────────────────────────────────
                  if (offerLabel != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        offerLabel!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                  Text(
                    '₹${offerPrice ?? item.displayPrice}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: offerPrice != null
                          ? const Color(0xFF2E7D32)
                          : null,
                    ),
                  ),
                  if (offerPrice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '₹${item.price}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ] else if (item.hasDiscount) ...[
                    const SizedBox(width: 6),
                    Text(
                      '₹${item.price}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text(
                    item.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Color(0xFFFFB300),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: item.image.isNotEmpty
                      ? Image.network(
                          item.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFEEEEEE),
                            child: const Center(
                              child: Icon(
                                Icons.fastfood_rounded,
                                size: 36,
                                color: Color(0xFFBDBDBD),
                              ),
                            ),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: const Color(0xFFEEEEEE),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFBDBDBD),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: const Color(0xFFEEEEEE),
                          child: const Center(
                            child: Icon(
                              Icons.fastfood_rounded,
                              size: 36,
                              color: Color(0xFFBDBDBD),
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 0,
                child: count > 0
                    // ── Stepper: − count + ──────────────────────────────
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: onDecrement,
                                  child: const SizedBox(
                                    width: 28,
                                    height: 26,
                                    child: Icon(
                                      Icons.remove_rounded,
                                      color: AppColors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: onIncrement,
                                  child: const SizedBox(
                                    width: 28,
                                    height: 26,
                                    child: Icon(
                                      Icons.add_rounded,
                                      color: AppColors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    // ── Plain Add button ─────────────────────────────────
                    : GestureDetector(
                        onTap: onAdd,
                        child: Container(
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            '+ Add',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
