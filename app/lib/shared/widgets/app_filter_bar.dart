import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class FilterOption<T> {
  final T value;
  final String label;
  final int? count;
  final IconData? icon;

  const FilterOption({
    required this.value,
    required this.label,
    this.count,
    this.icon,
  });
}

/// Horizontal scrollable filter bar with active indicators and count badges.
class AppFilterBar<T> extends StatelessWidget {
  final List<FilterOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const AppFilterBar({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isSelected = opt.value == selectedValue;

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(opt.value),
                borderRadius: AppRadius.rPill,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryMuted : AppColors.surfaceElevated,
                    borderRadius: AppRadius.rPill,
                    border: Border.all(
                      color: isSelected ? AppColors.primaryLight : AppColors.borderSubtle,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (opt.icon != null) ...[
                        Icon(
                          opt.icon,
                          size: 14.0,
                          color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Text(
                        opt.label,
                        style: AppTypography.labelSm.copyWith(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (opt.count != null) ...[
                        const SizedBox(width: AppSpacing.xs + 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.surfaceHover,
                            borderRadius: AppRadius.rPill,
                          ),
                          child: Text(
                            opt.count.toString(),
                            style: AppTypography.caption.copyWith(
                              fontSize: 10.0,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
