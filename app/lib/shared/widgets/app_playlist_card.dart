import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_status_badge.dart';

/// Reusable playlist overview card with artwork, counts, and sync status.
class AppPlaylistCard extends StatelessWidget {
  final String title;
  final int totalTracks;
  final int lockerTracks;
  final int missingTracks;
  final String? syncStatus;
  final String? lastSyncedText;
  final String? artworkUrl;
  final VoidCallback? onTap;
  final VoidCallback? onSync;
  final bool isSyncing;

  const AppPlaylistCard({
    super.key,
    required this.title,
    required this.totalTracks,
    required this.lockerTracks,
    required this.missingTracks,
    this.syncStatus,
    this.lastSyncedText,
    this.artworkUrl,
    this.onTap,
    this.onSync,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final percent = totalTracks > 0 ? (lockerTracks / totalTracks).clamp(0.0, 1.0) : 1.0;
    final isFullySynced = missingTracks == 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        hoverColor: AppColors.surfaceHover,
        child: Container(
          padding: AppSpacing.card,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.borderSubtle, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Playlist Artwork
                  ClipRRect(
                    borderRadius: AppRadius.rSm,
                    child: Container(
                      width: 56.0,
                      height: 56.0,
                      color: AppColors.surfaceElevated,
                      child: artworkUrl != null && artworkUrl!.isNotEmpty
                          ? Image.network(
                              artworkUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Title & Metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          '$totalTracks tracks • $lockerTracks in locker',
                          style: AppTypography.bodySm,
                        ),
                        if (missingTracks > 0) ...[
                          const SizedBox(height: 2.0),
                          Text(
                            '$missingTracks missing from locker',
                            style: AppTypography.caption.copyWith(color: AppColors.warning),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Status Badge or Sync Action
                  if (onSync != null)
                    IconButton(
                      icon: isSyncing
                          ? const SizedBox(
                              width: 18.0,
                              height: 18.0,
                              child: CircularProgressIndicator(strokeWidth: 2.0, color: AppColors.primaryLight),
                            )
                          : const Icon(Icons.sync_rounded, size: 20.0, color: AppColors.textSecondary),
                      onPressed: isSyncing ? null : onSync,
                      tooltip: 'Sync now',
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Sync Progress Bar
              ClipRRect(
                borderRadius: AppRadius.rPill,
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 4.0,
                  backgroundColor: AppColors.surfaceElevated,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFullySynced ? AppColors.success : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppStatusBadge(
                    type: isFullySynced ? SyncStatusType.uploaded : SyncStatusType.needsReview,
                    customLabel: syncStatus ?? (isFullySynced ? 'Synced' : '$missingTracks Missing'),
                    isDense: true,
                  ),
                  if (lastSyncedText != null)
                    Text(
                      lastSyncedText!,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Icon(
        Icons.playlist_play_rounded,
        size: 30.0,
        color: AppColors.textSecondary,
      ),
    );
  }
}
