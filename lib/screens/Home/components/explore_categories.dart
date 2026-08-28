import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/restaurant.dart';
import '../../../services/firestore_service.dart';
import '../../category/category_screen.dart';

/// Home Explore — Admin `restaurantCategories` (cuisine types).
class ExploreCategories extends StatelessWidget {
  const ExploreCategories({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explore',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 14),
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
                  return const Center(child: CircularProgressIndicator());
                }

                if (cats.isEmpty) {
                  // Soft fallback while Admin seeds restaurantCategories
                  cats = const [
                    RestaurantCategory(id: '1', name: 'Biryani', status: 'active'),
                    RestaurantCategory(id: '2', name: 'Chinese', status: 'active'),
                    RestaurantCategory(id: '3', name: 'South Indian', status: 'active'),
                    RestaurantCategory(id: '4', name: 'Pizza', status: 'active'),
                    RestaurantCategory(id: '5', name: 'Burgers', status: 'active'),
                  ];
                }

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _CategoryChip(item: cats[i]),
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
  const _CategoryChip({required this.item});

  final RestaurantCategory item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryScreen(categoryName: item.name),
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
                color: const Color(0xFFF5F5F5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
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
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
