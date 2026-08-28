import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../models/food_item.dart';
import '../../models/restaurant.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_controller.dart';
import '../checkout/cart_summary_screen.dart';
import '../location/select_location_screen.dart';
import 'addons_sheet.dart';

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
  String? _filter; // veg | nonveg | top
  String? _selectedCategoryId;
  bool _favorite = false;

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

  Future<void> _openAddons(FoodItem item) async {
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

    final result = await AddonsSheet.show(
      context,
      item: item,
      restaurantId: _resolvedId.isNotEmpty ? _resolvedId : item.restaurantId,
    );
    if (result == null || !mounted) return;

    final added = cart.tryAddItem(
      item: item,
      quantity: result.quantity,
      addons: result.addons,
      instructions: result.instructions,
    );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a delivery address to add items'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);
    final id = _resolvedId;

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
            filter: _filter,
            selectedCategoryId: _selectedCategoryId,
            favorite: _favorite,
            cart: cart,
            onFilter: (v) => setState(() => _filter = _filter == v ? null : v),
            onCategory: (cid) => setState(() {
              _selectedCategoryId = _selectedCategoryId == cid ? null : cid;
            }),
            onFavorite: () => setState(() => _favorite = !_favorite),
            onAdd: _openAddons,
          );
        },
      );
    }

    return _MenuBody(
      restaurant: widget.restaurant,
      restaurantId: '',
      restaurantName: _resolvedName,
      filter: _filter,
      selectedCategoryId: _selectedCategoryId,
      favorite: _favorite,
      cart: cart,
      onFilter: (v) => setState(() => _filter = _filter == v ? null : v),
      onCategory: (cid) => setState(() {
        _selectedCategoryId = _selectedCategoryId == cid ? null : cid;
      }),
      onFavorite: () => setState(() => _favorite = !_favorite),
      onAdd: _openAddons,
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
    required this.favorite,
    required this.cart,
    required this.onFilter,
    required this.onCategory,
    required this.onFavorite,
    required this.onAdd,
  });

  final Restaurant? restaurant;
  final String restaurantId;
  final String restaurantName;
  final String? filter;
  final String? selectedCategoryId;
  final bool favorite;
  final CartController cart;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onCategory;
  final VoidCallback onFavorite;
  final Future<void> Function(FoodItem) onAdd;

  Stream<QuerySnapshot> get _itemsStream {
    if (restaurantId.isNotEmpty) {
      return FirestoreService.foodItemsForRestaurant(restaurantId);
    }
    return FirestoreService.foodItemsByRestaurantName(restaurantName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: StreamBuilder<QuerySnapshot>(
        stream: _itemsStream,
        builder: (context, itemsSnap) {
          if (itemsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var items = (itemsSnap.data?.docs ?? [])
              .map(FoodItem.fromDoc)
              .where((f) {
                final active = f.status.isEmpty || f.status == 'active';
                return f.name.isNotEmpty && active;
              })
              .toList();

          // Name fallback if restaurantId query returned empty (legacy docs)
          if (items.isEmpty && restaurantId.isNotEmpty) {
            return StreamBuilder<QuerySnapshot>(
              stream:
                  FirestoreService.foodItemsByRestaurantName(restaurantName),
              builder: (context, nameSnap) {
                final byName = (nameSnap.data?.docs ?? [])
                    .map(FoodItem.fromDoc)
                    .where((f) => f.name.isNotEmpty)
                    .toList();
                return _buildContent(context, byName);
              },
            );
          }

          return _buildContent(context, items);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<FoodItem> rawItems) {
    var items = List<FoodItem>.from(rawItems);

    if (filter == 'veg') {
      items = items.where((f) => f.isVeg).toList();
    } else if (filter == 'nonveg') {
      items = items.where((f) => !f.isVeg).toList();
    } else if (filter == 'top') {
      items = items.where((f) => f.rating >= 4.0).toList();
    }

    if (selectedCategoryId != null) {
      items = items
          .where((f) =>
              f.categoryId == selectedCategoryId ||
              f.categoryName == selectedCategoryId)
          .toList();
    }

    final rating = restaurant?.rating ??
        (items.isEmpty
            ? 0.0
            : items.map((e) => e.rating).reduce((a, b) => a + b) / items.length);
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

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.share_outlined),
                      ),
                      IconButton(
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite ? AppColors.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurantName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
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
                          const SizedBox(height: 6),
                          Text(
                            '$delivery · $location',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cuisine.isEmpty ? 'Multi Cuisine' : cuisine,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                          if (restaurant != null && restaurant!.minOrder > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Min order ₹${restaurant!.minOrder}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A8A8A),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppColors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.35),
                  ),
                ),
                child: const Text(
                  'Free Delivery On ₹299 Above',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                child: _MenuFilters(selected: filter, onChanged: onFilter),
              ),
            ),
            // Restaurant food categories from Firestore
            if (restaurantId.isNotEmpty)
              SliverToBoxAdapter(
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      FirestoreService.foodCategoriesForRestaurant(restaurantId),
                  builder: (context, catSnap) {
                    final cats = (catSnap.data?.docs ?? [])
                        .map(FoodCategory.fromDoc)
                        .where((c) =>
                            c.name.isNotEmpty &&
                            (c.status.isEmpty || c.status == 'active'))
                        .toList()
                      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

                    if (cats.isEmpty) {
                      // Derive from items if Admin categories not seeded
                      final names = rawItems
                          .map((e) => e.categoryName)
                          .where((e) => e.isNotEmpty)
                          .toSet()
                          .toList();
                      if (names.isEmpty) return const SizedBox.shrink();
                      return _CategoryChips(
                        labels: names,
                        selected: selectedCategoryId,
                        onTap: onCategory,
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
                          final on = selectedCategoryId == c.id ||
                              selectedCategoryId == c.name;
                          return GestureDetector(
                            onTap: () => onCategory(c.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: on ? AppColors.primary : AppColors.white,
                                borderRadius: BorderRadius.circular(20),
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
            if (items.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No menu items for this restaurant')),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  cart.isEmpty ? 100 : 140,
                ),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 28),
                  itemBuilder: (context, index) {
                    return _MenuItemTile(
                      item: items[index],
                      onAdd: () => onAdd(items[index]),
                    );
                  },
                ),
              ),
          ],
        ),
        Positioned(
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
        ),
        if (!cart.isEmpty)
          Positioned(
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
          ),
      ],
    );
  }

  void _showMenuJump(BuildContext context, List<FoodItem> items) {
    final cats = <String, int>{};
    for (final i in items) {
      final key = i.categoryName.isEmpty ? 'Popular' : i.categoryName;
      cats[key] = (cats[key] ?? 0) + 1;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Menu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...cats.entries.map(
                (e) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  trailing: Text('${e.value}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onCategory(e.key);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
                borderRadius: BorderRadius.circular(20),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOn ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOn ? AppColors.primary : const Color(0xFFDDDDDD),
                ),
              ),
              child: Row(
                children: [
                  if (isDot)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOn ? AppColors.white : color,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: isOn ? AppColors.white : color,
                      ),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOn ? AppColors.white : const Color(0xFF1A1A1A),
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

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.onAdd});

  final FoodItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
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
                  Text(
                    '₹${item.displayPrice}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.hasDiscount) ...[
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
                  const Icon(Icons.star_rounded,
                      size: 14, color: Color(0xFFFFB300)),
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
                      ? Image.network(item.image, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFFEEEEEE),
                          child: const Icon(Icons.fastfood_rounded),
                        ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: -12,
                child: GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
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
                        fontSize: 13,
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
