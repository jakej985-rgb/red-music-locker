import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_status_badge.dart';

/// Artwork-first grid card for tracks in Library and Uploads views.
class AppTrackGridCard extends StatelessWidget {
  final String title;
  final String artist;
  final String? artworkUrl;
  final SyncStatusType? statusType;
  final String? statusLabel;
  final bool isSelected;
  final bool showCheckbox;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback? onTap;

  const AppTrackGridCard({
    super.key,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.statusType,
    this.statusLabel,
    this.isSelected = false,
    this.showCheckbox = false,
    this.onSelectionChanged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        hoverColor: AppColors.surfaceHover,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryMuted.withValues(alpha: 0.2) : AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: isSelected ? AppColors.primaryLight : AppColors.borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Square Artwork
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: AppRadius.rSm,
                        child: Container(
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
                    ),
                    if (showCheckbox)
                      Positioned(
                        top: 4.0,
                        right: 4.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: onSelectionChanged,
                            activeColor: AppColors.primary,
                            side: const BorderSide(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    if (statusType != null)
                      Positioned(
                        bottom: 6.0,
                        left: 6.0,
                        child: AppStatusBadge(
                          type: statusType!,
                          customLabel: statusLabel,
                          isDense: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Track Info
              Text(
                title.isNotEmpty ? title : 'Untitled',
                style: AppTypography.label.copyWith(
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
      ),
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Icon(
        Icons.music_note_rounded,
        size: 36.0,
        color: AppColors.textMuted,
      ),
    );
  }
}
