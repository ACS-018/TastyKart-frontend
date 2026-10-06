import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../widgets/app_screen_header.dart';
import '../Home/components/free_delivery_banner.dart';
import '../location/select_location_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Settings',
            subtitle: 'Your Account Settings',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  // ── Free delivery banner ──────────────────────────────
                  const FreeDeliveryBanner(showHorizontalMargin: false),
                  const SizedBox(height: 24),
                  const Text(
                    'Other Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Add a Place',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'In case we are missing something',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const SelectLocationScreen(manageOnly: true),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Notifications',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    value: _notificationsOn,
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.35),
                    onChanged: (v) => setState(() => _notificationsOn = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
