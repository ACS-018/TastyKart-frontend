import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/restaurant.dart';
import '../../../services/firestore_service.dart';
import '../../category/category_screen.dart';

/// Home Explore — Admin `restaurantCategories` (cuisine types).
class ExploreCategories extends StatelessWidget {
  const ExploreCategories({
    super.key,
    this.showTitle = true,
    this.onPrimary = false,
  });

  final bool showTitle;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final textColor = onPrimary ? AppColors.white : const Color(0xFF1A1A1A);
    final chipBg = onPrimary
        ? AppColors.white.withValues(alpha: 0.15)
        : const Color(0xFFF5F5F5);
    final shadowColor = onPrimary
        ? Colors.black.withValues(alpha: 0.0)
        : Colors.black.withValues(alpha: 0.1);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, showTitle ? 20 : 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Text(
              'Explore',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            height: 96,
            child: StreamBuilder(
              stream: FirestoreService.activeRestaurantCategories(),
              builder: (context, snapshot) {
                var cats = (snapshot.data?.docs ?? [])
                    .map(RestaurantCategory.fromDoc)
                    .where((c) => c.name.isNotEmpty)
                    .toList();

                if (cats.isEmpty &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: onPrimary ? AppColors.white : AppColors.primary,
                    ),
                  );
                }

                if (cats.isEmpty) {
                  cats = const [
                    RestaurantCategory(
                      id: '1',
                      name: 'Biryani',
                      status: 'active',
                    ),
                    RestaurantCategory(
                      id: '2',
                      name: 'Chinese',
                      status: 'active',
                    ),
                    RestaurantCategory(
                      id: '3',
                      name: 'South Indian',
                      status: 'active',
                    ),
                    RestaurantCategory(
                      id: '4',
                      name: 'Pizza',
                      status: 'active',
                    ),
                    RestaurantCategory(
                      id: '5',
                      name: 'Burgers',
                      status: 'active',
                    ),
                  ];
                }

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _CategoryChip(
                    item: cats[i],
                    textColor: textColor,
                    chipBg: chipBg,
                    shadowColor: shadowColor,
                    onPrimary: onPrimary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.item,
    required this.textColor,
    required this.chipBg,
    required this.shadowColor,
    required this.onPrimary,
  });

  final RestaurantCategory item;
  final Color textColor;
  final Color chipBg;
  final Color shadowColor;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CategoryScreen(categoryName: item.name, categoryId: item.id),
          ),
        );
      },
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chipBg,
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: item.imageUrl.isNotEmpty
                    ? Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _letter(),
                      )
                    : _letter(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letter() {
    return Center(
      child: Text(
        item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: onPrimary ? AppColors.primary : AppColors.primary,
        ),
      ),
    );
  }
}
