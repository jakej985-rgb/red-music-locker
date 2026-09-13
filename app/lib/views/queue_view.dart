import 'dart:async';
import 'package:flutter/material.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../shared/widgets/shared_widgets.dart';
import 'components/metadata_editor_dialog.dart';

class QueueView extends StatefulWidget {
  const QueueView({super.key});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  String _activeCategory = 'all'; // all, needs_help, metadata_change, download, upload, local_upload
  Map<String, int> _summary = {
    'all': 0,
    'needs_help': 0,
    'metadata_change': 0,
    'download': 0,
    'upload': 0,
    'local_upload': 0,
    'active': 0,
  };
  List<UnifiedQueueItem> _items = [];
  bool _isActive = false;
  String _activeDescription = '';
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    // Poll every 2.5 seconds so user sees live download/upload/metadata progress
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _loadQueue(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQueue({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final res = await apiService.getUnifiedQueue(
        category: _activeCategory,
        limit: 250,
      );
      if (mounted) {
        setState(() {
          _summary = res.summary;
          _items = res.items;
          _isActive = res.isActive;
          _activeDescription = res.activeDescription;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _enqueueMissing() async {
    try {
      final count = await apiService.uploadAllMissing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enqueued $count missing local tracks'),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Cancel Active Tasks?'),
        content: const Text('This will cancel any active playlist sync or download and clear queued upload jobs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Tasks'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await apiService.cancelAllQueue();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Active tasks cancelled'),
              backgroundColor: AppColors.surfaceElevated,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadQueue();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _clearFinished() async {
    try {
      await apiService.clearCompletedQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cleared finished task history'),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _dismissHelp(String videoId) async {
    try {
      await apiService.dismissNeedsHelpTrack(videoId);
      _loadQueue();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'needs_help':
        return AppColors.warning;
      case 'metadata_change':
        return Colors.orangeAccent;
      case 'download':
        return AppColors.info;
      case 'local_upload':
        return AppColors.success;
      case 'upload':
      default:
        return AppColors.streaming;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'needs_help':
        return Icons.help_outline_rounded;
      case 'metadata_change':
        return Icons.edit_note_rounded;
      case 'download':
        return Icons.download_rounded;
      case 'local_upload':
        return Icons.drive_folder_upload_rounded;
      case 'upload':
      default:
        return Icons.cloud_upload_rounded;
    }
  }

  String _getCategoryLabel(String key) {
    switch (key) {
      case 'needs_help':
        return 'Needs Help';
      case 'metadata_change':
        return 'Metadata Change';
      case 'download':
        return 'Download';
      case 'upload':
        return 'Upload';
      case 'local_upload':
        return 'Local Upload';
      case 'all':
      default:
        return 'All';
    }
  }

  Widget _buildTelemetryGrid() {
    final activeCount = _summary['active'] ?? (_isActive ? 1 : 0);
    final helpCount = _summary['needs_help'] ?? 0;
    final totalCount = _summary['all'] ?? _items.length;
    final uploadCount = (_summary['upload'] ?? 0) + (_summary['local_upload'] ?? 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 900
                ? 4
                : 4;

        final cards = [
          AppStatCard(
            title: 'ACTIVE',
            value: '$activeCount',
            icon: Icons.play_circle_outline_rounded,
            accentColor: activeCount > 0 ? AppColors.primary : AppColors.textMuted,
            subtitle: activeCount > 0 ? 'Operations in flight' : 'Idle',
            onTap: () {
              setState(() => _activeCategory = 'all');
              _loadQueue();
            },
          ),
          AppStatCard(
            title: 'ATTENTION',
            value: '$helpCount',
            icon: Icons.warning_amber_rounded,
            accentColor: helpCount > 0 ? AppColors.warning : AppColors.textMuted,
            subtitle: helpCount > 0 ? 'Action required' : 'None',
            onTap: () {
              setState(() => _activeCategory = 'needs_help');
              _loadQueue();
            },
          ),
          AppStatCard(
            title: 'IN PIPELINE',
            value: '$totalCount',
            icon: Icons.layers_rounded,
            accentColor: AppColors.info,
            subtitle: 'Queued operations',
            onTap: () {
              setState(() => _activeCategory = 'all');
              _loadQueue();
            },
          ),
          AppStatCard(
            title: 'UPLOADS',
            value: '$uploadCount',
            icon: Icons.cloud_upload_outlined,
            accentColor: AppColors.streaming,
            subtitle: 'Cloud sync queue',
            onTap: () {
              setState(() => _activeCategory = 'upload');
              _loadQueue();
            },
          ),
        ];

        if (crossAxisCount == 2) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }

        return Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: c,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildCategoryChip(String key) {
    final isSelected = _activeCategory == key;
    final count = _summary[key] ?? 0;
    final color = _getCategoryColor(key);

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: isSelected ? null : Icon(_getCategoryIcon(key), size: 16, color: color),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getCategoryLabel(key),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white24 : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceSubtle,
        selectedColor: color.withValues(alpha: 0.25),
        side: BorderSide(
          color: isSelected ? color : AppColors.borderSubtle,
          width: isSelected ? 1.5 : 1,
        ),
        onSelected: (_) {
          if (_activeCategory != key) {
            setState(() => _activeCategory = key);
            _loadQueue();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final totalCount = _summary[_activeCategory] ?? _items.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            AppPageHeader(
              title: 'Queue',
              kicker: 'OPERATIONS & PIPELINE',
              subtitle: _activeDescription.isNotEmpty
                  ? '$totalCount items • $_activeDescription'
                  : '$totalCount items currently in pipeline',
              actions: [
                if (_isActive) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                    onPressed: _cancelAll,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Cancel Active'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  onPressed: _clearFinished,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Clear Finished'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  onPressed: _enqueueMissing,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Add Missing'),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Refresh Queue',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _loadQueue(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.button,
                      side: BorderSide(color: AppColors.borderSubtle),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Top Telemetry Stats Cards
            _buildTelemetryGrid(),
            const SizedBox(height: AppSpacing.lg),

            // Active Activity Live Banner
            if (_isActive && _activeDescription.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.2),
                      AppColors.streaming.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _activeDescription,
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Category Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryChip('all'),
                  _buildCategoryChip('needs_help'),
                  _buildCategoryChip('metadata_change'),
                  _buildCategoryChip('download'),
                  _buildCategoryChip('upload'),
                  _buildCategoryChip('local_upload'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Queue Items List
            if (_isLoading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60.0),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: AppEmptyState(
                  icon: _getCategoryIcon(_activeCategory),
                  title: 'Queue is Clear',
                  description: _activeCategory == 'all'
                      ? 'No active, queued, or recently completed tasks.'
                      : 'No operations currently pending in ${_getCategoryLabel(_activeCategory)}.',
                  actionLabel: 'Add All Missing Tracks',
                  onAction: _enqueueMissing,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final isInProgress = item.status == 'in_progress';
                  final isCompleted = item.status == 'completed';
                  final isFailed = item.status == 'failed';
                  final isNeedsHelp = item.status == 'needs_help';
                  final catColor = _getCategoryColor(item.category);

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: AppRadius.card,
                      border: Border.all(
                        color: isInProgress
                            ? catColor.withValues(alpha: 0.5)
                            : isNeedsHelp
                                ? AppColors.warning.withValues(alpha: 0.5)
                                : isFailed
                                    ? AppColors.error.withValues(alpha: 0.4)
                                    : AppColors.borderSubtle,
                        width: (isInProgress || isNeedsHelp) ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Item index
                        SizedBox(
                          width: 32,
                          child: Text(
                            '#${index + 1}',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),

                        // Thumbnail or category icon
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: item.thumbnail != null && item.thumbnail!.isNotEmpty
                              ? Image.network(
                                  item.thumbnail!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    _getCategoryIcon(item.category),
                                    color: catColor,
                                    size: 22,
                                  ),
                                )
                              : Icon(
                                  _getCategoryIcon(item.category),
                                  color: catColor,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 14),

                        // Title, Artist & Album, Step, Source
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.h3,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (item.artist != null && item.artist!.isNotEmpty)
                                    Flexible(
                                      child: Text(
                                        item.artist!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.bodySm.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  if (item.album != null && item.album!.isNotEmpty)
                                    Text(
                                      ' • ${item.album!}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                ],
                              ),
                              if (item.currentStep != null && item.currentStep!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  item.currentStep!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(
                                    color: isInProgress
                                        ? catColor
                                        : isFailed
                                            ? AppColors.error
                                            : AppColors.textMuted,
                                    fontWeight: isInProgress ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Source badge
                        if (item.source != null && item.source!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.source!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],

                        // Status Badge & Actions
                        if (isNeedsHelp) ...[
                          const AppStatusBadge(
                            type: SyncStatusType.needsReview,
                            customLabel: 'Needs Help',
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                              foregroundColor: AppColors.warning,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                            ),
                            onPressed: () async {
                              final videoId = item.videoId ?? item.id.replaceFirst('help_', '').replaceFirst('pl_help_', '');
                              final res = await MetadataEditorDialog.showForTrack(
                                context,
                                videoId: videoId,
                                title: item.title,
                                artist: item.artist,
                                album: item.album,
                                thumbnail: item.thumbnail,
                              );
                              if (res != null) {
                                _loadQueue();
                              }
                            },
                            icon: const Icon(Icons.search_rounded, size: 15),
                            label: const Text('Find Match', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Dismiss',
                            icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                            onPressed: () {
                              final videoId = item.videoId ?? item.id.replaceFirst('help_', '').replaceFirst('pl_help_', '');
                              _dismissHelp(videoId);
                            },
                          ),
                        ] else ...[
                          AppStatusBadge.fromString(
                            isInProgress
                                ? 'syncing'
                                : isCompleted
                                    ? 'uploaded'
                                    : isFailed
                                        ? 'failed'
                                        : 'pending',
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
