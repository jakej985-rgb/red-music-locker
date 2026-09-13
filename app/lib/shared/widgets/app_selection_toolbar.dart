import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Floating contextual toolbar for bulk selection actions.
class AppSelectionToolbar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClearSelection;
  final VoidCallback? onSelectAll;
  final List<Widget> actions;

  const AppSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    this.onSelectAll,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: AppColors.primaryMuted, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18.0),
            onPressed: onClearSelection,
            tooltip: 'Clear selection',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$selectedCount selected',
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (onSelectAll != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onSelectAll,
              child: const Text('Select All'),
            ),
          ],
          const SizedBox(width: AppSpacing.md),
          Container(width: 1.0, height: 20.0, color: AppColors.divider),
          const SizedBox(width: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}
