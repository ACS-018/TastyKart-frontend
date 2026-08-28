import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/color_constants.dart';
import '../profile/favorites_screen.dart';
import '../profile/order_history_screen.dart';
import '../profile/profile_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _currentNavIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      extendBody: true,
      appBar: _currentNavIndex == 0 ? const HomeAppBar() : null,
      body: IndexedStack(
        index: _currentNavIndex,
        children: const [
          _HomeTabBody(),
          OrderHistoryScreen(embedded: true),
          FavoritesScreen(embedded: true),
          ProfileScreen(embedded: true),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
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
        onTap: (i) => setState(() => _currentNavIndex = i),
      ),
    );
  }
}

class _HomeTabBody extends StatelessWidget {
  const _HomeTabBody();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SearchBarWidget(),
          const BannerCarousel(),
          Container(
            color: const Color(0xFFF9F9F9),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExploreCategories(),
                FreeDeliveryBanner(),
                ActiveOrderCard(),
                FilterChipsRow(),
                RestaurantGrid(),
                FeaturedList(),
                SubscriptionCard(),
                SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      shadowColor: Colors.black.withOpacity(0.12),
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
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 24),
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
