import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          // ── Search field ──────────────────────────────────────────────────
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.search_rounded,
                    color: AppColors.textMedium,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search For Food Or Kitchens',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Veg Mode toggle ───────────────────────────────────────────────
          _VegModeToggle(),
        ],
      ),
    );
  }
}

class _VegModeToggle extends StatefulWidget {
  @override
  State<_VegModeToggle> createState() => _VegModeToggleState();
}

class _VegModeToggleState extends State<_VegModeToggle> {
  bool _isVeg = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isVeg = !_isVeg),
          child: Container(
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _isVeg ? const Color(0xFF2E7D32) : AppColors.textLight,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: _isVeg ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Veg Mode',
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
