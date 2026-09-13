import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_status_badge.dart';

/// Standardized track list row with artwork thumbnail, metadata, status, and actions.
class AppTrackRow extends StatelessWidget {
  final String title;
  final String artist;
  final String? album;
  final String? duration;
  final String? artworkUrl;
  final SyncStatusType? statusType;
  final String? statusLabel;
  final bool isSelected;
  final bool showCheckbox;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback? onTap;
  final List<Widget>? actions;

  const AppTrackRow({
    super.key,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
    this.statusType,
    this.statusLabel,
    this.isSelected = false,
    this.showCheckbox = false,
    this.onSelectionChanged,
    this.onTap,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.primaryMuted.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        hoverColor: AppColors.surfaceHover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle.withValues(alpha: 0.5), width: 1),
            ),
          ),
          child: Row(
            children: [
              if (showCheckbox) ...[
                SizedBox(
                  width: 24.0,
                  height: 24.0,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: onSelectionChanged,
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                    semanticLabel: 'Select $title',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              // Artwork Thumbnail
              ClipRRect(
                borderRadius: AppRadius.rSm,
                child: Container(
                  width: 40.0,
                  height: 40.0,
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
              // Title & Artist
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Untitled Track',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      artist.isNotEmpty ? artist : 'Unknown Artist',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Album (Desktop / wide)
              if (album != null && album!.isNotEmpty)
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Text(
                      album!,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              // Status Badge
              if (statusType != null) ...[
                AppStatusBadge(
                  type: statusType!,
                  customLabel: statusLabel,
                  isDense: true,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              // Duration
              if (duration != null && duration!.isNotEmpty) ...[
                Text(
                  duration!,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              // Context Actions
              if (actions != null && actions!.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!,
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
        Icons.music_note_rounded,
        size: 20.0,
        color: AppColors.textMuted,
      ),
    );
  }
}
