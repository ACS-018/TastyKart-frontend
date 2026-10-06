import 'package:flutter/material.dart';

import '../../../constants/color_constants.dart';
import '../../../state/diet_filter_controller.dart';
import '../../../utils/app_feedback.dart';
import '../../search/global_search_screen.dart';

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key});

  void _openSearch(BuildContext context, DietFilterController diet) {
    GlobalSearchScreen.open(context, dietMode: diet.mode);
  }

  @override
  Widget build(BuildContext context) {
    final diet = DietFilterScope.of(context);

    return ListenableBuilder(
      listenable: diet,
      builder: (context, _) {
        return Container(
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(30),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openSearch(context, diet),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          const Icon(
                            Icons.search_rounded,
                            color: AppColors.textMedium,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Search For Food Or Kitchens',
                              style: TextStyle(
                                color: AppColors.textLight,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _openSearch(context, diet),
                            icon: const Icon(
                              Icons.mic_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _DietModeToggle(
                isVeg: diet.isVegMode,
                onChanged: (veg) {
                  AppFeedback.selection();
                  diet.setVegMode(veg);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact veg-mode toggle — FSSAI square dot + Switch + label below.
class _DietModeToggle extends StatelessWidget {
  const _DietModeToggle({required this.isVeg, required this.onChanged});

  final bool isVeg;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return GestureDetector(
      onTap: () => onChanged(!isVeg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle track
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: isVeg
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(child: _VegDot(isVeg: isVeg, size: 8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FSSAI-standard square border with circle dot inside.
class _VegDot extends StatelessWidget {
  const _VegDot({required this.isVeg, this.size = 14});
  final bool isVeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? AppColors.white : AppColors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
