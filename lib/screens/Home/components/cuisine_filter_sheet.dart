import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../models/restaurant.dart';
import '../../../services/firestore_service.dart';

class CuisineFilterSheet extends StatefulWidget {
  const CuisineFilterSheet({super.key, this.initiallySelected = const {}});

  /// Set of **category IDs** (Firestore doc IDs) that are pre-selected.
  final Set<String> initiallySelected;

  /// Returns a [Set] of selected **category IDs**, or null if dismissed.
  static Future<Set<String>?> show(
    BuildContext context, {
    Set<String> initiallySelected = const {},
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CuisineFilterSheet(initiallySelected: initiallySelected),
    );
  }

  @override
  State<CuisineFilterSheet> createState() => _CuisineFilterSheetState();
}

class _CuisineFilterSheetState extends State<CuisineFilterSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
  }

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
              // ── Handle ──────────────────────────────────────────────────
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Title row ───────────────────────────────────────────────
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

              // ── List — streamed from restaurantCategories ────────────────
              Expanded(
                child: StreamBuilder(
                  stream: FirestoreService.activeRestaurantCategories(),
                  builder: (context, snapshot) {
                    // Loading
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }

                    // Map Firestore docs → category names (active only,
                    // already filtered by the query).
                    final cats =
                        (snapshot.data?.docs ?? [])
                            .map(RestaurantCategory.fromDoc)
                            .where((c) => c.name.trim().isNotEmpty)
                            .toList()
                          // Respect sortOrder if present, else keep Firestore order.
                          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

                    if (cats.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No categories available',
                            style: TextStyle(color: Color(0xFF999999)),
                          ),
                        ),
                      );
                    }

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      children: [
                        _sectionTitle('Cuisines'),
                        const SizedBox(height: 8),
                        // Pass the full category so we can key by ID while
                        // displaying the human-readable name.
                        ...cats.map((c) => _checkboxTile(c.id, c.name)),
                      ],
                    );
                  },
                ),
              ),

              // ── Action buttons ──────────────────────────────────────────
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => setState(() => _selected.clear()),
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
                          onPressed: () => Navigator.pop(
                            context,
                            Set<String>.from(_selected),
                          ),
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

  Widget _checkboxTile(String id, String label) {
    final checked = _selected.contains(id);
    return CheckboxListTile(
      value: checked,
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(id);
          } else {
            _selected.remove(id);
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
