import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/color_constants.dart';
import '../../utils/app_feedback.dart';
import '../../state/cart_controller.dart';
import '../../state/diet_filter_controller.dart';
import '../checkout/cart_summary_screen.dart';
import '../profile/favorites_screen.dart';
import '../profile/order_history_screen.dart';
import '../profile/profile_screen.dart';
import '../search/global_search_screen.dart';
import 'components/home_app_bar.dart';
import 'components/search_bar_widget.dart';
import 'components/banner_carousel.dart';
import 'components/explore_categories.dart';
import 'components/free_delivery_banner.dart';
import 'components/active_order_card.dart';
import 'components/filter_chips_row.dart';
import 'components/restaurant_grid.dart';
import 'components/featured_list.dart';
import 'components/subscription_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _currentNavIndex;
  final ScrollController _homeScrollController = ScrollController();
  int _homeRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _currentNavIndex = widget.initialTab;
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) {
      AppFeedback.selection();
      if (index == 0 && _homeScrollController.hasClients) {
        _homeScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    AppFeedback.light();
    setState(() => _currentNavIndex = index);
  }

  Future<void> _refreshHome() async {
    setState(() => _homeRefreshToken++);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Nav bar height (60) + system bottom inset
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const navBarHeight = 60.0;
    final cartBarBottom = navBarHeight + bottomInset + 56;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          extendBody: true,
          appBar: _currentNavIndex == 0 ? const HomeAppBar() : null,
          body: IndexedStack(
            index: _currentNavIndex,
            children: [
              _HomeTabBody(
                scrollController: _homeScrollController,
                refreshToken: _homeRefreshToken,
                onRefresh: _refreshHome,
              ),
              const OrderHistoryScreen(embedded: true),
              const FavoritesScreen(embedded: true),
              const ProfileScreen(embedded: true),
            ],
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              AppFeedback.light();
              final diet = DietFilterScope.maybeOf(context);
              GlobalSearchScreen.open(
                context,
                dietMode: diet?.mode ?? DietMode.nonVeg,
              );
            },
            backgroundColor: AppColors.primary,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.white,
              size: 28,
            ),
          ),
          bottomNavigationBar: _HomeBottomNav(
            currentIndex: _currentNavIndex,
            onTap: _onNavTap,
          ),
        ),

        // ── Floating cart bar above nav bar ──────────────────────────────
        Positioned(
          left: 16,
          right: 16,
          bottom: cartBarBottom,
          child: ListenableBuilder(
            listenable: CartScope.of(context),
            builder: (context, _) {
              final cart = CartScope.of(context);
              return AnimatedSlide(
                offset: cart.isEmpty ? const Offset(0, 1.5) : Offset.zero,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: cart.isEmpty ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  child: cart.isEmpty
                      ? const SizedBox.shrink()
                      : _CartFloatingBar(cart: cart),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeTabBody extends StatefulWidget {
  const _HomeTabBody({
    required this.scrollController,
    required this.refreshToken,
    required this.onRefresh,
  });

  final ScrollController scrollController;
  final int refreshToken;
  final Future<void> Function() onRefresh;

  @override
  State<_HomeTabBody> createState() => _HomeTabBodyState();
}

class _HomeTabBodyState extends State<_HomeTabBody> {
  // Threshold: once the user has scrolled past the banners (~244px = search72 + banners220 - appbar ~48)
  static const double _stickyThreshold = 244;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_HomeTabBody old) {
    super.didUpdateWidget(old);
    if (old.scrollController != widget.scrollController) {
      old.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final scrolled =
        widget.scrollController.hasClients &&
        widget.scrollController.offset > _stickyThreshold;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // ── Scrollable top ─────────────────────────────────────────────
          const SliverToBoxAdapter(child: SearchBarWidget()),
          const SliverToBoxAdapter(child: BannerCarousel()),

          // ── Pinned header — swaps layout based on scroll position ──────
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              isScrolled: _isScrolled,
              refreshToken: widget.refreshToken,
            ),
          ),

          // ── Scrollable content below ───────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFFF9F9F9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FreeDeliveryBanner(),
                  const ActiveOrderCard(),
                  RestaurantGrid(
                    key: ValueKey('restaurants_${widget.refreshToken}'),
                  ),
                  FeaturedList(
                    key: ValueKey('featured_${widget.refreshToken}'),
                  ),
                  const SubscriptionCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned header that swaps between two layouts based on scroll position.
/// Height is fixed — layout is driven by [isScrolled] from the scroll controller.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyHeaderDelegate({
    required this.isScrolled,
    required this.refreshToken,
  });

  final bool isScrolled;
  final int refreshToken;

  // Fixed height covers the taller of the two layouts (sticky = 230px).
  static const double _height = 230;

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    if (isScrolled) {
      // Compact sticky — primary background
      return SizedBox(
        height: _height,
        child: Container(
          color: AppColors.primary,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SearchBarWidget(),
              ExploreCategories(showTitle: false, onPrimary: true),
              FilterChipsRow(onPrimary: true),
            ],
          ),
        ),
      );
    }

    // Normal at-top — white/light background, Explore title visible
    return SizedBox(
      height: _height,
      child: Container(
        color: const Color(0xFFF9F9F9),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExploreCategories(showTitle: true, onPrimary: false),
            FilterChipsRow(onPrimary: false),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate old) =>
      old.isScrolled != isScrolled || old.refreshToken != refreshToken;
}

class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: AppColors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              selected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Orders',
              selected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            const SizedBox(width: 48),
            _NavItem(
              icon: Icons.favorite_border_rounded,
              activeIcon: Icons.favorite_rounded,
              label: 'Favourites',
              selected: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
              selected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: AppColors.primary.withValues(alpha: 0.04),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? activeIcon : icon,
                key: ValueKey(selected),
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Floating cart bar ─────────────────────────────────────────────────────────

class _CartFloatingBar extends StatelessWidget {
  const _CartFloatingBar({required this.cart});

  final CartController cart;

  @override
  Widget build(BuildContext context) {
    final itemCount = cart.itemCount;
    final total = cart.itemsTotal;
    final restaurantName = cart.primaryRestaurantName ?? 'your order';

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(16),
      color: AppColors.primary,
      shadowColor: AppColors.primary.withValues(alpha: 0.35),
      child: InkWell(
        onTap: () {
          AppFeedback.light();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartSummaryScreen()),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // ── Cart icon badge ───────────────────────────────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.white,
                    size: 26,
                  ),
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$itemCount',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),

              // ── Item count + restaurant name ──────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$itemCount item${itemCount > 1 ? 's' : ''} in cart',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Total ─────────────────────────────────────────────────
              Text(
                '₹$total',
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),

              // ── View cart label ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // ── Clear cart button ─────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  AppFeedback.light();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Text(
                        'Clear Cart?',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      content: const Text('Remove all items from your cart?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    CartScope.of(context).clear();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
