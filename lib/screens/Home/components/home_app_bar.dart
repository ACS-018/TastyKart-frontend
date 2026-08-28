import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../location/select_location_screen.dart';
import '../../notifications/notifications_screen.dart';
import '../../profile/profile_screen.dart';
import '../../../state/cart_controller.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.maybeOf(context);
    final hasAddress = cart?.hasDeliveryAddress == true;
    final locationLabel = hasAddress
        ? (cart!.selectedAddress!.isDefault
            ? '${cart.selectedAddress!.label} · ${cart.selectedAddress!.fullAddress}'
            : cart.selectedAddress!.fullAddress)
        : 'Add delivery address';
    final shortLabel = hasAddress
        ? locationLabel.split(',').take(2).join(',')
        : locationLabel;

    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      titleSpacing: 16,
      title: GestureDetector(
        onTap: () async {
          final address = await SelectLocationScreen.pick(context);
          if (address != null && context.mounted) {
            CartScope.of(context).setAddress(address);
          }
        },
        child: Row(
          children: [
            Icon(
              hasAddress
                  ? Icons.location_on_outlined
                  : Icons.add_location_alt_outlined,
              color: AppColors.white,
              size: 18,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                shortLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.white,
              size: 18,
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          },
          icon: const Icon(
            Icons.notifications_outlined,
            color: AppColors.white,
            size: 24,
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          icon: const Icon(
            Icons.account_circle_outlined,
            color: AppColors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
