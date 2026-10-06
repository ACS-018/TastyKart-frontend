import 'package:flutter/material.dart';

import '../../../constants/color_constants.dart';
import '../../../state/home_filter_controller.dart';
import '../../../utils/app_feedback.dart';
import 'cuisine_filter_sheet.dart';

/// Horizontal filter row — "Filter ▼ | New to you | Offers | Ratings 4.0+"
/// Matches the Figma design: small radius (8), outlined chips, no pill shape.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({super.key, this.onPrimary = false});

  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final filters = HomeFilterScope.of(context);

    return ListenableBuilder(
      listenable: filters,
      builder: (context, _) {
        final activeChip = filters.chip;
        final hasCuisine = filters.cuisines.isNotEmpty;

        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // ── Filter (cuisine sheet) ─────────────────────────────────
              _FilterDropChip(
                active: hasCuisine,
                onPrimary: onPrimary,
                onTap: () async {
                  AppFeedback.selection();
                  final picked = await CuisineFilterSheet.show(
                    context,
                    initiallySelected: filters.cuisines,
                  );
                  if (picked != null) {
                    filters.setCuisines(picked);
                  }
                },
              ),
              const SizedBox(width: 8),

              // ── New to you ─────────────────────────────────────────────
              _Chip(
                label: 'New to you',
                selected: activeChip == HomeChipFilter.newToYou,
                onPrimary: onPrimary,
                onTap: () {
                  AppFeedback.selection();
                  filters.toggleChip(HomeChipFilter.newToYou);
                },
              ),
              const SizedBox(width: 8),

              // ── Offers ─────────────────────────────────────────────────
              _Chip(
                label: 'Offers',
                selected: activeChip == HomeChipFilter.offers,
                onPrimary: onPrimary,
                onTap: () {
                  AppFeedback.selection();
                  filters.toggleChip(HomeChipFilter.offers);
                },
              ),
              const SizedBox(width: 8),

              // ── Ratings 4.0+ ───────────────────────────────────────────
              _Chip(
                label: 'Ratings 4.0+',
                selected: activeChip == HomeChipFilter.ratings4Plus,
                onPrimary: onPrimary,
                onTap: () {
                  AppFeedback.selection();
                  filters.toggleChip(HomeChipFilter.ratings4Plus);
                },
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFFFB300),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Filter ▼" chip that opens the cuisine bottom sheet.
class _FilterDropChip extends StatelessWidget {
  const _FilterDropChip({
    required this.active,
    required this.onPrimary,
    required this.onTap,
  });

  final bool active;
  final bool onPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? AppColors.primary
        : onPrimary
        ? AppColors.white.withValues(alpha: 0.18)
        : AppColors.white;
    final textColor = active
        ? AppColors.white
        : onPrimary
        ? AppColors.white
        : const Color(0xFF1A1A1A);
    final borderColor = active
        ? AppColors.primary
        : onPrimary
        ? AppColors.white.withValues(alpha: 0.5)
        : const Color(0xFFDDDDDD);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 15, color: textColor),
            const SizedBox(width: 5),
            Text(
              'Filter',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: textColor),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onPrimary,
    required this.onTap,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool selected;
  final bool onPrimary;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primary
        : onPrimary
        ? AppColors.white.withValues(alpha: 0.18)
        : AppColors.white;
    final textColor = selected
        ? AppColors.white
        : onPrimary
        ? AppColors.white
        : const Color(0xFF1A1A1A);
    final borderColor = selected
        ? AppColors.primary
        : onPrimary
        ? AppColors.white.withValues(alpha: 0.5)
        : const Color(0xFFDDDDDD);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.white : (iconColor ?? textColor),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
