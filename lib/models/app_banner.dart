import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin `banners/{id}` — see tapAction / restaurant / webUrl fields.
enum BannerTapAction { none, restaurant, webUrl }

class AppBanner {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String status;
  final BannerTapAction tapAction;
  final String? restaurantId;
  final String? restaurantName;
  final String? webUrl;
  final String? link;
  final int sortOrder;

  const AppBanner({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.imageUrl,
    required this.status,
    this.tapAction = BannerTapAction.none,
    this.restaurantId,
    this.restaurantName,
    this.webUrl,
    this.link,
    this.sortOrder = 0,
  });

  factory AppBanner.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppBanner(
      id: _nonEmpty(data['id'] as String?) ?? doc.id,
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      status: data['status'] as String? ?? '',
      tapAction: _parseTapAction(data['tapAction'] as String?),
      restaurantId: _nonEmpty(data['restaurantId'] as String?),
      restaurantName: _nonEmpty(data['restaurantName'] as String?),
      webUrl: _nonEmpty(data['webUrl'] as String?),
      link: _nonEmpty(data['link'] as String?),
      sortOrder: (data['order'] as num? ?? data['sortOrder'] as num? ?? 0)
          .toInt(),
    );
  }

  /// Action to perform on tap, including legacy `link` inference.
  BannerTapAction get effectiveTapAction {
    if (tapAction != BannerTapAction.none) return tapAction;

    final legacy = link;
    if (legacy == null || legacy.isEmpty) return BannerTapAction.none;
    if (_isWebUrl(legacy)) return BannerTapAction.webUrl;
    if (_restaurantIdFromLink(legacy) != null) {
      return BannerTapAction.restaurant;
    }
    return BannerTapAction.none;
  }

  bool get isTappable => effectiveTapAction != BannerTapAction.none;

  String? get effectiveRestaurantId {
    if (restaurantId != null && restaurantId!.isNotEmpty) return restaurantId;
    return _restaurantIdFromLink(link);
  }

  String? get effectiveRestaurantName {
    if (restaurantName != null && restaurantName!.isNotEmpty) {
      return restaurantName;
    }
    return null;
  }

  String? get effectiveWebUrl {
    if (webUrl != null && webUrl!.isNotEmpty) return webUrl;
    if (effectiveTapAction == BannerTapAction.webUrl &&
        link != null &&
        _isWebUrl(link!)) {
      return link;
    }
    return null;
  }

  static BannerTapAction _parseTapAction(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'restaurant':
        return BannerTapAction.restaurant;
      case 'web_url':
      case 'weburl':
      case 'web':
        return BannerTapAction.webUrl;
      default:
        return BannerTapAction.none;
    }
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isWebUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// Legacy admin paths like `/restaurants/{id}`.
  static String? _restaurantIdFromLink(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'(?:/)?restaurants/([^/?#]+)',
    ).firstMatch(value.trim());
    return match?.group(1);
  }
}
