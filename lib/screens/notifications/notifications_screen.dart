import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_screen_header.dart';
import '../../widgets/async_state_message.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _refreshToken = 0;

  Future<void> _onRefresh() async {
    setState(() => _refreshToken++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  List<AppNotification> get _sampleNotifications => [
    AppNotification(
      id: 'sample_1',
      title: 'Welcome to ${AppConstants.appName}! 🎉',
      message:
          'Your favorite meals are now just a tap away. Start exploring restaurants near you.',
      type: 'promo',
      read: false,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    AppNotification(
      id: 'sample_2',
      title: 'Free Delivery Offer',
      message:
          'Get free delivery on all orders above ₹49. Limited time offer — order now!',
      type: 'offer',
      read: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      id: 'sample_3',
      title: 'Your Order is Being Prepared',
      message:
          'The chef is cooking your Biryani. It will be ready for delivery in 15 minutes.',
      type: 'order',
      read: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
    AppNotification(
      id: 'sample_4',
      title: 'New Restaurant Near You',
      message:
          'Biryani Bliss has just opened 2 km away. Check out their signature dishes!',
      type: 'info',
      read: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  IconData _iconFor(String type) {
    switch (type.toLowerCase()) {
      case 'order':
        return Icons.receipt_long_rounded;
      case 'offer':
      case 'promo':
        return Icons.local_offer_rounded;
      case 'payment':
        return Icons.payment_rounded;
      case 'delivery':
        return Icons.delivery_dining_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type.toLowerCase()) {
      case 'order':
        return const Color(0xFF2E7D32);
      case 'offer':
      case 'promo':
        return AppColors.primary;
      case 'payment':
        return const Color(0xFF1565C0);
      case 'delivery':
        return const Color(0xFFE65100);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Notifications',
            subtitle: 'Your Incoming Notifications',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<QuerySnapshot>(
                key: ValueKey(_refreshToken),
                stream: FirestoreService.notificationsUnordered(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _buildList(_sampleNotifications, fallback: true);
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const AsyncStateMessage.loading();
                  }

                  var notes = (snapshot.data?.docs ?? [])
                      .map(AppNotification.fromDoc)
                      .where((n) => n.title.isNotEmpty)
                      .toList();

                  notes.sort((a, b) {
                    final aa =
                        a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bb =
                        b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bb.compareTo(aa);
                  });

                  final useFallback = notes.isEmpty;
                  final displayList = useFallback
                      ? _sampleNotifications
                      : notes;

                  if (displayList.isEmpty) {
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _onRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          AsyncStateMessage(
                            icon: Icons.notifications_none_rounded,
                            message: 'No notifications yet',
                          ),
                        ],
                      ),
                    );
                  }

                  return _buildList(displayList, fallback: useFallback);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AppNotification> notes, {bool fallback = false}) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Row(
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (fallback)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Sample',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...notes.map((n) {
            final accent = _colorFor(n.type);
            final icon = _iconFor(n.type);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                n.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: n.read
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  color: n.read
                                      ? AppColors.textMedium
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                            if (!n.read)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(left: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          n.message,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B6B6B),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          n.timeAgo,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9E9E9E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
