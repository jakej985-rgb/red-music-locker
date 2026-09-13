import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Global persistent sync status indicator for the application shell.
class AppSyncStatusIndicator extends StatelessWidget {
  final DashboardStats? stats;
  final bool compact;
  final VoidCallback? onTap;
  final double? width;

  const AppSyncStatusIndicator({
    super.key,
    this.stats,
    this.compact = false,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final ytm = apiService.ytmAccount;
    final isConnected = ytm?.isConnected ?? false;
    final isUploading = stats?.isUploading ?? false;
    final isScanning = stats?.isScanning ?? false;
    final pendingCount = stats?.inQueueCount ?? 0;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isUploading) {
      statusText = 'Uploading...';
      statusColor = AppColors.info;
      statusIcon = Icons.sync;
    } else if (isScanning) {
      statusText = 'Scanning...';
      statusColor = AppColors.warning;
      statusIcon = Icons.radar;
    } else if (!isConnected) {
      statusText = 'YTM Disconnected';
      statusColor = AppColors.textMuted;
      statusIcon = Icons.cloud_off_outlined;
    } else if (pendingCount > 0) {
      statusText = '↑ $pendingCount queued';
      statusColor = AppColors.warning;
      statusIcon = Icons.cloud_upload_outlined;
    } else {
      statusText = '✓ Synced';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_outline;
    }

    if (compact) {
      return InkWell(
        onTap: onTap,
        borderRadius: AppRadius.badge,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: AppRadius.badge,
            border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUploading || isScanning)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: statusColor,
                  ),
                )
              else
                Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: AppTypography.caption.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.card,
      child: Container(
        width: width ?? 190,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isConnected ? 'YTM Connected' : 'Disconnected',
                          style: AppTypography.caption.copyWith(
                            color: isConnected ? AppColors.textPrimary : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      if (pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.warningBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '↑ $pendingCount',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        )
                      else if (isUploading || isScanning)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.info,
                          ),
                        )
                      else
                        const Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: AppColors.success,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats != null
                        ? '${stats!.uploadedCount} uploaded • ${stats!.missingCount} missing'
                        : (isConnected ? 'Online' : 'Offline'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 9,
                    ),
                    overflow: TextOverflow.ellipsis,
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
