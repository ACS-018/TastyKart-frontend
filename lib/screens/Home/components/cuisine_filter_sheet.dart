import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';

class CuisineFilterSheet extends StatefulWidget {
  const CuisineFilterSheet({super.key});

  static Future<Set<String>?> show(BuildContext context) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CuisineFilterSheet(),
    );
  }

  @override
  State<CuisineFilterSheet> createState() => _CuisineFilterSheetState();
}

class _CuisineFilterSheetState extends State<CuisineFilterSheet> {
  final Set<String> _selected = {};

  static const List<String> _cuisines = [
    'South Indian',
    'North Indian',
    'Andhra Special',
    'Biryani',
    'Chinese',
    'Italian',
    'Continental',
    'Mexican',
  ];

  static const List<String> _moreOptions = [
    'Indian',
    'Fast Food',
    'Desserts',
    'Beverages',
    'Healthy',
    'Seafood',
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: [
                    _sectionTitle('Cuisines'),
                    const SizedBox(height: 8),
                    ..._cuisines.map(_checkboxTile),
                    const SizedBox(height: 16),
                    _sectionTitle('More Options'),
                    const SizedBox(height: 8),
                    ..._moreOptions.map(_checkboxTile),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() => _selected.clear());
                          },
                          child: const Text(
                            'Clear Filters',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(context, Set<String>.from(_selected)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _checkboxTile(String label) {
    final checked = _selected.contains(label);
    return CheckboxListTile(
      value: checked,
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(label);
          } else {
            _selected.remove(label);
          }
        });
      },
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
