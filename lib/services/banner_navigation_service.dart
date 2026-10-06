import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_banner.dart';
import '../screens/restaurant/restaurant_menu_screen.dart';
import '../utils/app_feedback.dart';
import '../utils/app_navigation.dart';

/// Handles banner tap → restaurant menu or external web URL.
class BannerNavigationService {
  BannerNavigationService._();

  static Future<void> handleTap(BuildContext context, AppBanner banner) async {
    if (!banner.isTappable) return;

    switch (banner.effectiveTapAction) {
      case BannerTapAction.none:
        return;
      case BannerTapAction.restaurant:
        await _openRestaurant(context, banner);
      case BannerTapAction.webUrl:
        await _openWebUrl(context, banner);
    }
  }

  static Future<void> _openRestaurant(
    BuildContext context,
    AppBanner banner,
  ) async {
    final id = banner.effectiveRestaurantId;
    if (id == null || id.isEmpty) {
      AppFeedback.showError(context, 'Restaurant link is not configured');
      return;
    }

    AppFeedback.light();
    await AppNavigation.push(
      context,
      RestaurantMenuScreen(
        restaurantId: id,
        restaurantName: banner.effectiveRestaurantName ?? 'Restaurant',
      ),
    );
  }

  static Future<void> _openWebUrl(
    BuildContext context,
    AppBanner banner,
  ) async {
    var url = banner.effectiveWebUrl;
    if (url == null || url.isEmpty) {
      AppFeedback.showError(context, 'Web link is not configured');
      return;
    }

    if (!url.toLowerCase().startsWith('http')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      AppFeedback.showError(context, 'Invalid web link');
      return;
    }

    AppFeedback.light();
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      AppFeedback.showError(context, 'Could not open link');
    }
  }
}
