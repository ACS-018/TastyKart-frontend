import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import 'cuisine_filter_sheet.dart';

class FilterChipsRow extends StatefulWidget {
  const FilterChipsRow({super.key});

  @override
  State<FilterChipsRow> createState() => _FilterChipsRowState();
}

class _FilterChipsRowState extends State<FilterChipsRow> {
  int _selectedIndex = -1;

  final List<_ChipData> _chips = const [
    _ChipData(label: 'Filter', hasIcon: true),
    _ChipData(label: 'New to you'),
    _ChipData(label: 'Offers'),
    _ChipData(label: 'Ratings 4.0+'),
  ];

  Future<void> _onChipTap(int index) async {
    if (index == 0) {
      await CuisineFilterSheet.show(context);
      return;
    }
    setState(() => _selectedIndex = _selectedIndex == index ? -1 : index);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_chips.length, (index) {
            final chip = _chips[index];
            final isSelected = _selectedIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _onChipTap(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : const Color(0xFFDDDDDD),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chip.hasIcon) ...[
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.textDark,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.textDark,
                        ),
                      ),
                      if (chip.hasIcon) ...[
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.textDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ChipData {
  final String label;
  final bool hasIcon;
  const _ChipData({required this.label, this.hasIcon = false});
}
