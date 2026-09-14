import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_status_badge.dart';

class AppActivityItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String timestamp;
  final SyncStatusType status;
  final IconData? icon;
  final VoidCallback? onTap;

  const AppActivityItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.timestamp,
    this.status = SyncStatusType.uploaded,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: icon != null
            ? Icon(icon, size: 20, color: AppColors.textSecondary)
            : null,
        title: Text(
          title,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusBadge(type: status, isDense: true),
            const SizedBox(width: AppSpacing.sm),
            Text(
              timestamp,
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
