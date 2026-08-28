import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../services/firestore_service.dart';

class BannerModel {
  final String id;
  final String title;
  final String imageUrl;
  final String status;
  final String? link;
  final int sortOrder;

  const BannerModel({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.status,
    this.link,
    this.sortOrder = 0,
  });

  factory BannerModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BannerModel(
      id: data['id'] as String? ?? doc.id,
      title: data['title'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      status: data['status'] as String? ?? '',
      link: data['link'] as String?,
      sortOrder: (data['order'] as num? ?? data['sortOrder'] as num? ?? 0)
          .toInt(),
    );
  }
}

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.78);
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.only(bottom: 20),
      child: SizedBox(
        height: 190,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirestoreService.activeBanners(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.white),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Failed to load banners',
                  style: TextStyle(color: AppColors.white),
                ),
              );
            }

            final banners = (snapshot.data?.docs ?? [])
                .map(BannerModel.fromDoc)
                .where((b) => b.imageUrl.isNotEmpty)
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            if (banners.isEmpty) {
              return const Center(
                child: Text(
                  'No banners available',
                  style: TextStyle(color: AppColors.white),
                ),
              );
            }

            return PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: banners.length,
              itemBuilder: (context, index) {
                final isActive = index == _currentPage;
                return AnimatedScale(
                  scale: isActive ? 1.0 : 0.90,
                  duration: const Duration(milliseconds: 300),
                  child: _BannerCard(
                    banner: banners[index],
                    isActive: isActive,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.isActive});

  final BannerModel banner;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              banner.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: AppColors.primary.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFB32B2C),
                child: const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
            // Gradient overlay for readable title
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.65),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ORDER NOW',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.white,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
