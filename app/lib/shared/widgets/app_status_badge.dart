import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum SyncStatusType {
  uploaded,
  localOnly,
  matched,
  needsReview,
  failed,
  duplicate,
  syncing,
  pending,
  streamingOnly,
}

/// Accessible, semantic status badge for tracks, uploads, and playlists.
class AppStatusBadge extends StatelessWidget {
  final SyncStatusType type;
  final String? customLabel;
  final bool isDense;

  const AppStatusBadge({
    super.key,
    required this.type,
    this.customLabel,
    this.isDense = false,
  });

  factory AppStatusBadge.fromString(String? status, {bool isDense = false}) {
    final s = (status ?? '').toLowerCase().trim();
    if (s.contains('uploaded') || s == 'success' || s == 'synced') {
      return AppStatusBadge(type: SyncStatusType.uploaded, isDense: isDense);
    }
    if (s.contains('local') || s.contains('locker_only') || s == 'missing') {
      return AppStatusBadge(type: SyncStatusType.localOnly, isDense: isDense);
    }
    if (s.contains('matched') || s == 'exact' || s == 'verified') {
      return AppStatusBadge(type: SyncStatusType.matched, isDense: isDense);
    }
    if (s.contains('review') || s.contains('needs_help') || s == 'ambiguous') {
      return AppStatusBadge(type: SyncStatusType.needsReview, isDense: isDense);
    }
    if (s.contains('fail') || s.contains('error')) {
      return AppStatusBadge(type: SyncStatusType.failed, isDense: isDense);
    }
    if (s.contains('dup') || s.contains('exists')) {
      return AppStatusBadge(type: SyncStatusType.duplicate, isDense: isDense);
    }
    if (s.contains('sync') || s.contains('uploading') || s == 'in_progress') {
      return AppStatusBadge(type: SyncStatusType.syncing, isDense: isDense);
    }
    if (s.contains('stream') || s == 'youtube_only' || s == 'catalog') {
      return AppStatusBadge(type: SyncStatusType.streamingOnly, isDense: isDense);
    }
    return AppStatusBadge(type: SyncStatusType.pending, isDense: isDense);
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(type);
    final text = customLabel ?? config.label;

    return Semantics(
      label: 'Status: $text',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDense ? AppSpacing.xs + 2 : AppSpacing.sm,
          vertical: isDense ? 2.0 : AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: config.backgroundColor,
          borderRadius: AppRadius.badge,
          border: Border.all(color: config.borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              config.icon,
              size: isDense ? 11.0 : 13.0,
              color: config.textColor,
            ),
            SizedBox(width: isDense ? 3.0 : 5.0),
            Text(
              text,
              style: (isDense ? AppTypography.caption : AppTypography.labelSm).copyWith(
                color: config.textColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusConfig _getConfig(SyncStatusType type) {
    switch (type) {
      case SyncStatusType.uploaded:
        return const _StatusConfig(
          label: 'Uploaded',
          icon: Icons.cloud_done_rounded,
          backgroundColor: AppColors.successBg,
          borderColor: Color(0x5510B981),
          textColor: AppColors.success,
        );
      case SyncStatusType.localOnly:
        return const _StatusConfig(
          label: 'Local Only',
          icon: Icons.computer_rounded,
          backgroundColor: Color(0x269E9E9E),
          borderColor: Color(0x559E9E9E),
          textColor: AppColors.textSecondary,
        );
      case SyncStatusType.matched:
        return const _StatusConfig(
          label: 'Matched',
          icon: Icons.verified_rounded,
          backgroundColor: AppColors.infoBg,
          borderColor: Color(0x553EA6FF),
          textColor: AppColors.info,
        );
      case SyncStatusType.needsReview:
        return const _StatusConfig(
          label: 'Needs Review',
          icon: Icons.help_outline_rounded,
          backgroundColor: AppColors.warningBg,
          borderColor: Color(0x55F59E0B),
          textColor: AppColors.warning,
        );
      case SyncStatusType.failed:
        return const _StatusConfig(
          label: 'Failed',
          icon: Icons.error_outline_rounded,
          backgroundColor: AppColors.errorBg,
          borderColor: Color(0x55EF4444),
          textColor: AppColors.error,
        );
      case SyncStatusType.duplicate:
        return const _StatusConfig(
          label: 'Duplicate',
          icon: Icons.copy_rounded,
          backgroundColor: Color(0x266B7280),
          borderColor: Color(0x556B7280),
          textColor: AppColors.textSecondary,
        );
      case SyncStatusType.syncing:
        return const _StatusConfig(
          label: 'Syncing',
          icon: Icons.sync_rounded,
          backgroundColor: AppColors.primaryMuted,
          borderColor: Color(0x55E50914),
          textColor: AppColors.primaryLight,
        );
      case SyncStatusType.pending:
        return const _StatusConfig(
          label: 'Pending',
          icon: Icons.hourglass_empty_rounded,
          backgroundColor: AppColors.pendingBg,
          borderColor: Color(0x556B7280),
          textColor: AppColors.textSecondary,
        );
      case SyncStatusType.streamingOnly:
        return const _StatusConfig(
          label: 'Streaming Only',
          icon: Icons.music_note_rounded,
          backgroundColor: AppColors.streamingBg,
          borderColor: Color(0x558B5CF6),
          textColor: AppColors.streaming,
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  const _StatusConfig({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });
}
