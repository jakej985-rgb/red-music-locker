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

class UploadsView extends StatefulWidget {
  const UploadsView({super.key});

  @override
  State<UploadsView> createState() => _UploadsViewState();
}

class _UploadsViewState extends State<UploadsView> {
  String _activeFilter = 'missing_metadata';
  final TextEditingController _searchController = TextEditingController();

  List<YtmUpload> _uploads = [];
  Map<String, int> _summary = {'total': 0, 'missing_metadata': 0, 'proper': 0};
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  final int _pageSize = 30;

  final Set<String> _selectedEntityIds = {};
  bool _isBatchProcessing = false;
  int _activeRequestId = 0;

  bool _isLoading = false;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSummaryAndData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSummaryAndData({int page = 1}) async {
    final requestId = ++_activeRequestId;
    final requestedFilter = _activeFilter;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summaryFuture = apiService.getYtmUploadsSummary();
      final uploadsFuture = apiService.getYtmUploads(
        filterType: requestedFilter,
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        page: page,
        pageSize: _pageSize,
      );

      final results = await Future.wait([summaryFuture, uploadsFuture]);
      if (!mounted || requestId != _activeRequestId || _activeFilter != requestedFilter) {
        return;
      }

      final summary = results[0] as Map<String, int>;
      final uploadsData = results[1];
      final newTotalPages = (uploadsData['total_pages'] as int?) ?? 1;
      if (page > newTotalPages && newTotalPages > 0) {
        _loadSummaryAndData(page: newTotalPages);
        return;
      }

      setState(() {
        _summary = summary;
        _uploads = List<YtmUpload>.from(uploadsData['items']);
        _totalCount = uploadsData['total'] as int;
        _currentPage = uploadsData['page'] as int;
        _totalPages = newTotalPages;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _activeRequestId) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerCloudSync() async {
    setState(() => _isSyncing = true);
    try {
      await apiService.triggerSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Syncing uploads from YouTube Music in the background...'),
            backgroundColor: AppColors.info,
          ),
        );
      }
      await Future.delayed(const Duration(seconds: 3));
      await _loadSummaryAndData(page: _currentPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sync: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openRetagDialog(YtmUpload upload) async {
    final result = await MetadataEditorDialog.showForYtmUpload(context, upload);
    if (result != null) {
      if (result is Map<String, dynamic> && result['saved'] == true) {
        final newTitle = result['title'] as String? ?? upload.title;
        final newArtist = result['artist'] as String?;
        final newAlbum = result['album'] as String?;
        final newCoverUrl = result['coverUrl'] as String? ?? upload.thumbnail;

        final updatedUpload = upload.copyWith(
          title: newTitle,
          artist: newArtist,
          album: newAlbum,
          thumbnail: newCoverUrl,
        );

        final stillMissing = updatedUpload.isMissingMetadata;

        setState(() {
          final index = _uploads.indexWhere((u) => u.entityId == upload.entityId);
          if (stillMissing) {
            if (index != -1) {
              _uploads[index] = updatedUpload;
            }
          } else {
            if (_activeFilter == 'missing_metadata') {
              _uploads.removeWhere((u) => u.entityId == upload.entityId);
              final currentMissing = _summary['missing_metadata'] ?? 0;
              final currentProper = _summary['proper'] ?? 0;
              _summary = {
                ..._summary,
                'missing_metadata': currentMissing > 0 ? currentMissing - 1 : 0,
                'proper': currentProper + 1,
              };
            } else if (index != -1) {
              _uploads[index] = updatedUpload;
            }
          }
        });
      }
      _loadSummaryAndData(page: _currentPage);
    }
  }

  Future<void> _confirmDelete(YtmUpload upload) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: AppSpacing.sm),
            Text('Delete from YouTube Music?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${upload.displayTitle}" from your YouTube Music cloud uploads? This action cannot be undone.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final ok = await apiService.deleteYtmUpload(upload.entityId);
        if (ok && mounted) {
          setState(() {
            _uploads.removeWhere((u) => u.entityId == upload.entityId);
            final currentTotal = _summary['total'] ?? 0;
            final currentMissing = _summary['missing_metadata'] ?? 0;
            _summary = {
              ..._summary,
              'total': currentTotal > 0 ? currentTotal - 1 : 0,
              'missing_metadata': currentMissing > 0 ? currentMissing - 1 : 0,
            };
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${upload.displayTitle}" from YouTube Music.'),
              backgroundColor: AppColors.success,
            ),
          );
          _loadSummaryAndData(page: _currentPage);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting upload: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _toggleSelectAllPage() {
    setState(() {
      final pageIds = _uploads.map((u) => u.entityId).toSet();
      if (_selectedEntityIds.containsAll(pageIds)) {
        _selectedEntityIds.removeAll(pageIds);
      } else {
        _selectedEntityIds.addAll(pageIds);
      }
    });
  }

  void _toggleSelectItem(String entityId) {
    setState(() {
      if (_selectedEntityIds.contains(entityId)) {
        _selectedEntityIds.remove(entityId);
      } else {
        _selectedEntityIds.add(entityId);
      }
    });
  }

  Future<void> _batchDeleteSelected() async {
    if (_selectedEntityIds.isEmpty) return;
    final count = _selectedEntityIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: AppColors.error, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Text('Delete $count Upload${count > 1 ? 's' : ''}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete $count selected upload${count > 1 ? 's' : ''} from YouTube Music? This action cannot be undone.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isBatchProcessing = true);
      try {
        final toDelete = _selectedEntityIds.toList();
        final res = await apiService.batchDeleteYtmUploads(toDelete);
        final deletedCount = res['deleted'] ?? toDelete.length;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully deleted $deletedCount upload${deletedCount > 1 ? 's' : ''} from YouTube Music.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _selectedEntityIds.clear();
        await _loadSummaryAndData(page: _currentPage);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to batch delete: $e'), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isBatchProcessing = false);
        }
      }
    }
  }

  Future<void> _batchAutoUploadSelected() async {
    if (_selectedEntityIds.isEmpty) return;
    final selectedUploads =
        _uploads.where((u) => _selectedEntityIds.contains(u.entityId)).toList();
    if (selectedUploads.isEmpty) return;

    final count = selectedUploads.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: AppColors.info, size: 22),
            SizedBox(width: AppSpacing.sm),
            Text('Auto-Tag & Upload Tracks?'),
          ],
        ),
        content: Text(
          'This will automatically clean up filenames, fetch high-res artwork, and replace/upload $count selected song${count > 1 ? 's' : ''} to YouTube Music.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.info),
            child: const Text('Start Upload'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isBatchProcessing = true);
      int successful = 0;
      int failed = 0;
      for (final upload in selectedUploads) {
        try {
          String cleanTitle = upload.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').trim();
          String cleanArtist = upload.artist ?? '';
          if (cleanTitle.contains(' - ') && cleanArtist.isEmpty) {
            final parts = cleanTitle.split(' - ');
            cleanArtist = parts[0].trim();
            cleanTitle = parts[1].trim();
          }
          final res = await apiService.replaceYtmUpload(
            upload.entityId,
            title: cleanTitle,
            artist: cleanArtist.isNotEmpty ? cleanArtist : null,
            album: upload.album,
            coverUrl: upload.thumbnail,
          );
          if (res['success'] == true) {
            successful++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Batch upload complete: $successful processed, $failed failed.'),
            backgroundColor: successful > 0 ? AppColors.success : AppColors.error,
          ),
        );
      }
      _selectedEntityIds.clear();
      await _loadSummaryAndData(page: _currentPage);
      if (mounted) {
        setState(() => _isBatchProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final missingCount = _summary['missing_metadata'] ?? 0;
    final duplicatesCount = _summary['duplicates'] ?? 0;
    final skitsCount = _summary['skits'] ?? 0;
    final totalCount = _summary['total'] ?? 0;
    final properCount = _summary['proper'] ?? 0;

    final filterOptions = [
      FilterOption(
        value: 'missing_metadata',
        label: 'Needs Metadata',
        count: missingCount,
        icon: Icons.warning_amber_rounded,
      ),
      FilterOption(
        value: 'duplicates',
        label: 'Duplicates',
        count: duplicatesCount,
        icon: Icons.copy_outlined,
      ),
      FilterOption(
        value: 'skits',
        label: 'Skits (<1m)',
        count: skitsCount,
        icon: Icons.timer_outlined,
      ),
      FilterOption(
        value: 'proper',
        label: 'Properly Tagged',
        count: properCount,
        icon: Icons.check_circle_outline,
      ),
      FilterOption(
        value: 'all',
        label: 'All Uploads',
        count: totalCount,
        icon: Icons.cloud_done_outlined,
      ),
    ];

    final pageIds = _uploads.map((u) => u.entityId).toSet();
    final isAllSelected = _uploads.isNotEmpty && _selectedEntityIds.containsAll(pageIds);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                AppPageHeader(
                  title: 'YOUTUBE MUSIC',
                  subtitle:
                      '$_totalCount tracks currently synchronized in your personal cloud locker',
                  kicker: 'CLOUD UPLOADS REPOSITORY',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _loadSummaryAndData(page: _currentPage),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isSyncing ? null : _triggerCloudSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_sync, size: 16),
                      label: Text(_isSyncing ? 'Syncing...' : 'Sync From YTM'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Search & Filter Bar
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppSearchBar(
                            hintText: 'Search uploads by title, artist, or album...',
                            controller: _searchController,
                            onSubmitted: (_) => _loadSummaryAndData(page: 1),
                            onClear: () {
                              _searchController.clear();
                              _loadSummaryAndData(page: 1);
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _toggleSelectAllPage,
                          icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 16),
                          label: Text(isAllSelected ? 'Deselect' : 'Select Page'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppFilterBar<String>(
                      options: filterOptions,
                      selectedValue: _activeFilter,
                      onSelected: (val) {
                        setState(() {
                          _activeFilter = val;
                          _selectedEntityIds.clear();
                        });
                        _loadSummaryAndData(page: 1);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Uploads List
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: AppLoadingState(message: 'Loading cloud uploads from YouTube Music...'),
                        )
                      : _errorMessage != null
                          ? Center(
                              child: AppErrorState(
                                title: 'Failed to Load Cloud Uploads',
                                message: _errorMessage!,
                                onRetry: () => _loadSummaryAndData(page: _currentPage),
                              ),
                            )
                          : _uploads.isEmpty
                              ? Center(
                                  child: AppEmptyState(
                                    icon: _activeFilter == 'missing_metadata'
                                        ? Icons.verified
                                        : Icons.cloud_off,
                                    title: _activeFilter == 'missing_metadata'
                                        ? 'Clean Metadata'
                                        : 'No Uploads Found',
                                    description: _activeFilter == 'missing_metadata'
                                        ? 'Every song in your YouTube Music locker has proper artist and album metadata!'
                                        : 'Try adjusting your search query or sync uploads from YouTube Music.',
                                    actionLabel: 'Sync Cloud',
                                    onAction: _triggerCloudSync,
                                  ),
                                )
                              : _buildUploadsList(),
                ),

                // Pagination Controls
                if (_totalPages > 1) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Showing ${_uploads.length} of $_totalCount uploads',
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: _currentPage > 1
                                ? () => _loadSummaryAndData(page: _currentPage - 1)
                                : null,
                          ),
                          Text(
                            'Page $_currentPage of $_totalPages',
                            style: AppTypography.label.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: _currentPage < _totalPages
                                ? () => _loadSummaryAndData(page: _currentPage + 1)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Floating Selection Toolbar
          if (_selectedEntityIds.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              child: Center(
                child: AppSelectionToolbar(
                  selectedCount: _selectedEntityIds.length,
                  onClearSelection: () => setState(() => _selectedEntityIds.clear()),
                  onSelectAll: _toggleSelectAllPage,
                  actions: [
                    if (_isBatchProcessing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.info,
                        ),
                      )
                    else ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.info,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        onPressed: _batchAutoUploadSelected,
                        icon: const Icon(Icons.cloud_upload, size: 16),
                        label: Text('Auto-Upload (${_selectedEntityIds.length})'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        onPressed: _batchDeleteSelected,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _uploads.length,
      itemBuilder: (context, index) {
        final upload = _uploads[index];
        final isSelected = _selectedEntityIds.contains(upload.entityId);
        final isUntagged = upload.isMissingMetadata;

        return AppTrackRow(
          title: upload.displayTitle,
          artist: upload.displayArtist,
          album: upload.album ?? 'Unknown Album',
          duration: upload.formattedDuration,
          artworkUrl: upload.thumbnail,
          statusType: isUntagged ? SyncStatusType.needsReview : SyncStatusType.uploaded,
          statusLabel: isUntagged ? 'Needs Metadata' : 'Uploaded',
          isSelected: isSelected,
          showCheckbox: true,
          onSelectionChanged: (_) => _toggleSelectItem(upload.entityId),
          onTap: () {
            if (_selectedEntityIds.isNotEmpty) {
              _toggleSelectItem(upload.entityId);
            } else {
              _openRetagDialog(upload);
            }
          },
          actions: [
            FilledButton.tonal(
              onPressed: () => _openRetagDialog(upload),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(
                isUntagged ? 'Retag & Replace' : 'Edit Tags',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Delete from YouTube Music',
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted),
              hoverColor: AppColors.error.withValues(alpha: 0.1),
              onPressed: () => _confirmDelete(upload),
            ),
          ],
        );
      },
    );
  }
}
