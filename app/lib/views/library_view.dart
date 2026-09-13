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
import 'components/upload_destination_dialog.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final TextEditingController _searchController = TextEditingController();
  List<MusicFile> _songs = [];
  bool _isLoading = false;
  String? _error;
  String _currentFilter = 'all';
  bool _isGridView = false;

  final Set<int> _selectedSongIds = {};
  bool _isBatchProcessing = false;

  final List<FilterOption<String>> _filterOptions = const [
    FilterOption(value: 'all', label: 'All Songs', icon: Icons.library_music_outlined),
    FilterOption(value: 'missing', label: 'Missing', icon: Icons.cloud_upload_outlined),
    FilterOption(value: 'uploaded', label: 'Uploaded', icon: Icons.check_circle_outline),
    FilterOption(value: 'queued', label: 'Queued', icon: Icons.hourglass_top_outlined),
    FilterOption(value: 'failed', label: 'Failed', icon: Icons.error_outline),
  ];

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SyncStatusType _mapStatusToSyncType(String status) {
    switch (status.toLowerCase()) {
      case 'uploaded':
      case 'verified':
      case 'exact':
        return SyncStatusType.uploaded;
      case 'queued':
        return SyncStatusType.pending;
      case 'uploading':
        return SyncStatusType.syncing;
      case 'failed':
        return SyncStatusType.failed;
      case 'not_uploaded':
      case 'missing':
      default:
        return SyncStatusType.localOnly;
    }
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final songs = await apiService.getSongs(
        status: _currentFilter,
        search: _searchController.text.trim(),
        limit: 300,
      );
      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _uploadTrack(MusicFile song) async {
    if (song.id == null) return;
    final res = await UploadDestinationDialog.show(context, [song]);
    if (res != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enqueued "${song.displayTitle}" for upload across ${res.jobsCreated} account(s)',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _loadSongs();
    }
  }

  Future<void> _openMetadataEditor(MusicFile song) async {
    final saved = await MetadataEditorDialog.show(context, song);
    if (saved == true) {
      _loadSongs();
    }
  }

  void _toggleSelectAll() {
    setState(() {
      final allIds = _songs.where((s) => s.id != null).map((s) => s.id!).toSet();
      if (_selectedSongIds.containsAll(allIds)) {
        _selectedSongIds.removeAll(allIds);
      } else {
        _selectedSongIds.addAll(allIds);
      }
    });
  }

  void _toggleSelectSong(int id) {
    setState(() {
      if (_selectedSongIds.contains(id)) {
        _selectedSongIds.remove(id);
      } else {
        _selectedSongIds.add(id);
      }
    });
  }

  Future<void> _batchUploadSelected() async {
    if (_selectedSongIds.isEmpty) return;
    final selectedSongs =
        _songs.where((s) => s.id != null && _selectedSongIds.contains(s.id!)).toList();
    final res = await UploadDestinationDialog.show(context, selectedSongs);
    if (res != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enqueued ${res.jobsCreated} upload jobs across ${res.destinations.length} account(s)!',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      _selectedSongIds.clear();
      await _loadSongs();
    }
  }

  Future<void> _batchDeleteSelected() async {
    if (_selectedSongIds.isEmpty) return;
    final count = _selectedSongIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: AppColors.error, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Text('Remove $count Track${count > 1 ? 's' : ''}?'),
          ],
        ),
        content: Text(
          'Remove $count selected track${count > 1 ? 's' : ''} from the locker library database? (Audio files on disk will NOT be deleted).',
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
            child: const Text('Remove All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isBatchProcessing = true);
      try {
        final deleted = await apiService.batchDeleteSongs(_selectedSongIds.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed $deleted song${deleted > 1 ? 's' : ''} from library.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        _selectedSongIds.clear();
        await _loadSongs();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Batch delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) setState(() => _isBatchProcessing = false);
      }
    }
  }

  void _showSongDetails(MusicFile song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: Text(song.displayTitle, style: AppTypography.h2),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Artist', song.displayArtist),
              _detailRow('Album', song.displayAlbum),
              _detailRow('Track #', song.trackNumber?.toString() ?? 'N/A'),
              _detailRow('Format', song.format.toUpperCase()),
              _detailRow('Duration', song.formattedDuration),
              _detailRow('File Size', song.formattedSize),
              _detailRow('Upload Status', song.uploadStatus.toUpperCase()),
              if (song.matchedUploadId != null)
                _detailRow('Matched YTM ID', song.matchedUploadId!),
              if (song.matchScore != null)
                _detailRow('Match Score', '${(song.matchScore! * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Disk Path',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.rSm,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: SelectableText(
                  song.path,
                  style: AppTypography.code.copyWith(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Metadata'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openMetadataEditor(song);
            },
          ),
          if (song.uploadStatus == 'not_uploaded' ||
              song.uploadStatus == 'failed' ||
              song.uploadStatus == 'missing')
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _uploadTrack(song);
              },
              child: const Text('Upload Now'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final allIds = _songs.where((s) => s.id != null).map((s) => s.id!).toSet();
    final isAllSelected = _songs.isNotEmpty && _selectedSongIds.containsAll(allIds);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? AppSpacing.md : AppSpacing.xl,
                  isMobile ? AppSpacing.md : AppSpacing.xl,
                  isMobile ? AppSpacing.md : AppSpacing.xl,
                  0,
                ),
                child: AppPageHeader(
                  title: 'MUSIC LIBRARY',
                  subtitle: '${_songs.length} tracks available in local locker repository',
                  kicker: 'LOCAL COLLECTION',
                  actions: [
                    IconButton(
                      icon: Icon(
                        _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: _isGridView ? 'Switch to List View' : 'Switch to Grid View',
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                    ),
                    OutlinedButton.icon(
                      onPressed: _toggleSelectAll,
                      icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 16),
                      label: Text(isAllSelected ? 'Deselect All' : 'Select All'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loadSongs,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Search and Filter Controls
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? AppSpacing.md : AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    AppSearchBar(
                      hintText: 'Search title, artist, album, format...',
                      controller: _searchController,
                      onSubmitted: (_) => _loadSongs(),
                      onClear: () {
                        _searchController.clear();
                        _loadSongs();
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppFilterBar<String>(
                      options: _filterOptions,
                      selectedValue: _currentFilter,
                      onSelected: (val) {
                        setState(() => _currentFilter = val);
                        _loadSongs();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Tracks Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: AppLoadingState(message: 'Loading local music files...'),
                      )
                    : _error != null
                        ? Center(
                            child: AppErrorState(
                              title: 'Failed to Load Tracks',
                              message: _error!,
                              onRetry: _loadSongs,
                            ),
                          )
                        : _songs.isEmpty
                            ? Center(
                                child: AppEmptyState(
                                  icon: Icons.music_off,
                                  title: 'No Tracks Found',
                                  description:
                                      'No audio tracks matched the selected filter "$_currentFilter" or search query.',
                                  actionLabel: 'Clear Search',
                                  onAction: () {
                                    _searchController.clear();
                                    setState(() => _currentFilter = 'all');
                                    _loadSongs();
                                  },
                                ),
                              )
                            : _isGridView
                                ? _buildGridView()
                                : _buildListView(),
              ),
            ],
          ),

          // Floating Selection Toolbar
          if (_selectedSongIds.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              child: Center(
                child: AppSelectionToolbar(
                  selectedCount: _selectedSongIds.length,
                  onClearSelection: () => setState(() => _selectedSongIds.clear()),
                  onSelectAll: _toggleSelectAll,
                  actions: [
                    if (_isBatchProcessing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    else ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                        onPressed: _batchUploadSelected,
                        icon: const Icon(Icons.cloud_upload, size: 16),
                        label: Text('Upload (${_selectedSongIds.length})'),
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
                        label: const Text('Remove'),
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

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.only(
        bottom: 80, // Allow space for floating toolbar
      ),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final isSelected = song.id != null && _selectedSongIds.contains(song.id!);

        return AppTrackRow(
          title: song.displayTitle,
          artist: song.displayArtist,
          album: song.displayAlbum,
          duration: song.formattedDuration,
          statusType: _mapStatusToSyncType(song.uploadStatus),
          isSelected: isSelected,
          showCheckbox: true,
          onSelectionChanged: song.id != null ? (_) => _toggleSelectSong(song.id!) : null,
          onTap: () {
            if (_selectedSongIds.isNotEmpty && song.id != null) {
              _toggleSelectSong(song.id!);
            } else {
              _showSongDetails(song);
            }
          },
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit Metadata',
              onPressed: () => _openMetadataEditor(song),
            ),
            if (song.uploadStatus == 'not_uploaded' ||
                song.uploadStatus == 'failed' ||
                song.uploadStatus == 'missing')
              FilledButton.tonal(
                onPressed: () => _uploadTrack(song),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
                child: const Text('Upload', style: TextStyle(fontSize: 12)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGridView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 4;
        if (constraints.maxWidth < 600) {
          crossAxisCount = 2;
        } else if (constraints.maxWidth < 900) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth > 1400) {
          crossAxisCount = 5;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.78,
          ),
          itemCount: _songs.length,
          itemBuilder: (context, index) {
            final song = _songs[index];
            final isSelected = song.id != null && _selectedSongIds.contains(song.id!);

            return AppTrackGridCard(
              title: song.displayTitle,
              artist: song.displayArtist,
              statusType: _mapStatusToSyncType(song.uploadStatus),
              isSelected: isSelected,
              showCheckbox: true,
              onSelectionChanged: song.id != null ? (_) => _toggleSelectSong(song.id!) : null,
              onTap: () {
                if (_selectedSongIds.isNotEmpty && song.id != null) {
                  _toggleSelectSong(song.id!);
                } else {
                  _showSongDetails(song);
                }
              },
            );
          },
        );
      },
    );
  }
}
