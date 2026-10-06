import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../constants/color_constants.dart';
import '../../../models/app_banner.dart';
import '../../../services/banner_navigation_service.dart';
import '../../../services/firestore_service.dart';

class BannerCarousel extends StatelessWidget {
  const BannerCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.only(bottom: 24),
      child: SizedBox(
        height: 220,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirestoreService.activeBanners(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
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

            final banners =
                (snapshot.data?.docs ?? [])
                    .map(AppBanner.fromDoc)
                    .where((b) => b.imageUrl.isNotEmpty)
                    .toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            if (banners.isEmpty) {
              return const SizedBox.shrink();
            }

            return _BannerPageView(banners: banners);
          },
        ),
      ),
    );
  }
}

class _BannerPageView extends StatefulWidget {
  const _BannerPageView({required this.banners});

  final List<AppBanner> banners;

  @override
  State<_BannerPageView> createState() => _BannerPageViewState();
}

class _BannerPageViewState extends State<_BannerPageView> {
  static const _autoScrollInterval = Duration(seconds: 4);
  static const _resumeDelay = Duration(seconds: 3);
  static const int _virtualMidPoint = 100000;

  late PageController _controller;
  Timer? _autoScrollTimer;
  int _currentVirtualPage = 0;
  bool _userInteracting = false;

  int get _realIndex => _currentVirtualPage % widget.banners.length;

  @override
  void initState() {
    super.initState();
    final startPage =
        _virtualMidPoint - (_virtualMidPoint % widget.banners.length);
    _currentVirtualPage = startPage;
    _controller = PageController(
      viewportFraction: 0.78,
      initialPage: startPage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
  }

  @override
  void didUpdateWidget(covariant _BannerPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      final startPage =
          _virtualMidPoint - (_virtualMidPoint % widget.banners.length);
      _currentVirtualPage = startPage;
      if (_controller.hasClients) {
        _controller.jumpToPage(startPage);
      }
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _controller.dispose();
    super.dispose();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _startAutoScroll() {
    _stopAutoScroll();
    if (widget.banners.length <= 1 || _userInteracting) return;

    _autoScrollTimer = Timer.periodic(
      _autoScrollInterval,
      (_) => _goToNextPage(),
    );
  }

  Future<void> _goToNextPage() async {
    if (!mounted || _userInteracting || widget.banners.length <= 1) return;
    if (!_controller.hasClients) return;

    final next = _currentVirtualPage + 1;
    try {
      await _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {}
  }

  void _onUserInteractionStart() {
    if (_userInteracting) return;
    _userInteracting = true;
    _stopAutoScroll();
  }

  void _onUserInteractionEnd() {
    if (!_userInteracting) return;
    _userInteracting = false;
    Future<void>.delayed(_resumeDelay, () {
      if (mounted && !_userInteracting) {
        _startAutoScroll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;

        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _onUserInteractionStart();
        } else if (notification is ScrollEndNotification) {
          _onUserInteractionEnd();
        }
        return false;
      },
      child: PageView.builder(
        controller: _controller,
        itemCount: null,
        onPageChanged: (index) {
          setState(() => _currentVirtualPage = index);
        },
        itemBuilder: (context, index) {
          final realIdx = index % widget.banners.length;
          final isActive = realIdx == _realIndex;
          return AnimatedScale(
            scale: isActive ? 1.0 : 0.90,
            duration: const Duration(milliseconds: 300),
            child: _BannerCard(
              banner: widget.banners[realIdx],
              isActive: isActive,
            ),
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.isActive});

  final AppBanner banner;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            Image.network(
              banner.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: AppColors.primary.withValues(alpha: 0.5),
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
            // Dark gradient overlay — stronger at bottom for text legibility
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.3, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            // Text + button overlay
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      banner.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // "ORDER NOW →" pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ORDER NOW',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.primary,
                          size: 13,
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

    if (!banner.isTappable) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => BannerNavigationService.handleTap(context, banner),
        borderRadius: BorderRadius.circular(22),
        child: content,
      ),
    );
  }
}
