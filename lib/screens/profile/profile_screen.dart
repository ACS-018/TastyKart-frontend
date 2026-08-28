import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../services/auth_service.dart';
import '../../state/cart_controller.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'order_history_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// When true, hides back navigation and uses as a tab body.
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _vegMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 20,
              right: 12,
              bottom: 24,
            ),
            color: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!widget.embedded)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.white,
                          size: 20,
                        ),
                      ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profile',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Your Available Profile',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xFFFFE8E8),
                      child: Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alena',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '+91 85688 67895',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Alena@gmail.com',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _vegMode,
                        onChanged: (v) => setState(() => _vegMode = v),
                        activeThumbColor: AppColors.primary,
                        activeTrackColor: AppColors.primary.withOpacity(0.35),
                        secondary: const Icon(
                          Icons.eco_rounded,
                          color: Color(0xFF2E7D32),
                        ),
                        title: const Text(
                          'Veg Mode',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Divider(height: 1),
                      _MenuTile(
                        icon: Icons.favorite_border_rounded,
                        label: 'Favourites',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FavoritesScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _MenuTile(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Orders',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OrderHistoryScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _MenuTile(
                        icon: Icons.settings_outlined,
                        label: 'Setting',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _MenuTile(
                        icon: Icons.logout_rounded,
                        label: 'Logout',
                        danger: true,
                        onTap: () async {
                          CartScope.maybeOf(context)?.clear();
                          await AuthService.logout();
                          // AuthGate returns to LoginScreen.
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: danger ? AppColors.error : const Color(0xFF1A1A1A),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.error : const Color(0xFF1A1A1A),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: danger ? AppColors.error : const Color(0xFFAAAAAA),
      ),
      onTap: onTap,
    );
  }
}
