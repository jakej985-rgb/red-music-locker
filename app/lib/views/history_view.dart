import 'package:flutter/material.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../shared/widgets/shared_widgets.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  List<SyncJob> _history = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, success, failed, pending

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await apiService.getHistory();
      if (mounted) {
        setState(() {
          _history = history;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<SyncJob> get _filteredHistory {
    return _history.where((job) {
      // Filter by status
      if (_statusFilter == 'success') {
        if (job.status != 'verified' && job.status != 'uploaded') return false;
      } else if (_statusFilter == 'failed') {
        if (job.status != 'failed') return false;
      } else if (_statusFilter == 'pending') {
        if (job.status == 'verified' || job.status == 'uploaded' || job.status == 'failed') return false;
      }

      // Filter by search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final title = (job.musicFile?.displayTitle ?? 'Track ID #${job.musicFileId}').toLowerCase();
        final artist = (job.musicFile?.displayArtist ?? '').toLowerCase();
        final album = (job.musicFile?.displayAlbum ?? '').toLowerCase();
        final path = (job.musicFile?.path ?? '').toLowerCase();
        final error = (job.error ?? '').toLowerCase();
        final entityId = (job.ytmEntityId ?? '').toLowerCase();

        return title.contains(q) ||
            artist.contains(q) ||
            album.contains(q) ||
            path.contains(q) ||
            error.contains(q) ||
            entityId.contains(q);
      }

      return true;
    }).toList();
  }

  Widget _buildTelemetryGrid() {
    final total = _history.length;
    final succeeded = _history.where((j) => j.status == 'verified' || j.status == 'uploaded').length;
    final failed = _history.where((j) => j.status == 'failed').length;
    final rate = total > 0 ? ((succeeded / total) * 100).round() : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 900
                ? 4
                : 4;

        final cards = [
          AppStatCard(
            title: 'TOTAL JOBS',
            value: '$total',
            icon: Icons.history_rounded,
            accentColor: AppColors.primaryLight,
            subtitle: 'Historical executions',
            onTap: () => setState(() => _statusFilter = 'all'),
          ),
          AppStatCard(
            title: 'SUCCEEDED',
            value: '$succeeded',
            icon: Icons.check_circle_outline_rounded,
            accentColor: AppColors.success,
            subtitle: 'Verified & uploaded',
            onTap: () => setState(() => _statusFilter = 'success'),
          ),
          AppStatCard(
            title: 'FAILED',
            value: '$failed',
            icon: Icons.error_outline_rounded,
            accentColor: failed > 0 ? AppColors.error : AppColors.textMuted,
            subtitle: failed > 0 ? 'Failed executions' : 'No errors',
            onTap: () => setState(() => _statusFilter = 'failed'),
          ),
          AppStatCard(
            title: 'SUCCESS RATE',
            value: '$rate%',
            icon: Icons.pie_chart_outline_rounded,
            accentColor: rate >= 90 ? AppColors.success : (rate >= 70 ? AppColors.warning : AppColors.error),
            subtitle: 'Overall reliability',
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

  Widget _buildFilterChip(String label, String value, int count, Color color) {
    final isSelected = _statusFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
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
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final filtered = _filteredHistory;
    final total = _history.length;
    final succeeded = _history.where((j) => j.status == 'verified' || j.status == 'uploaded').length;
    final failed = _history.where((j) => j.status == 'failed').length;
    final pending = total - succeeded - failed;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            AppPageHeader(
              title: 'Upload History & Activity',
              kicker: 'AUDIT TRAIL & LOGS',
              subtitle: '${filtered.length} of $total operations displayed',
              actions: [
                IconButton(
                  tooltip: 'Refresh History',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadHistory,
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

            // Telemetry Grid
            _buildTelemetryGrid(),
            const SizedBox(height: AppSpacing.lg),

            // Search Bar
            AppSearchBar(
              hintText: 'Search history by title, artist, album, error, or entity ID...',
              onChanged: (val) => setState(() => _searchQuery = val),
              onClear: () => setState(() => _searchQuery = ''),
            ),
            const SizedBox(height: AppSpacing.md),

            // Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', total, AppColors.info),
                  _buildFilterChip('Succeeded', 'success', succeeded, AppColors.success),
                  _buildFilterChip('Failed', 'failed', failed, AppColors.error),
                  _buildFilterChip('Pending', 'pending', pending, AppColors.warning),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // List of History Items
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60.0),
                child: AppLoadingState(message: 'Loading operation history...'),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: AppEmptyState(
                  icon: Icons.history_rounded,
                  title: _searchQuery.isNotEmpty ? 'No Matching Records' : 'No History Recorded',
                  description: _searchQuery.isNotEmpty
                      ? 'No history records matched your search query "$_searchQuery".'
                      : 'No upload or sync operations have been logged yet.',
                  actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : null,
                  onAction: _searchQuery.isNotEmpty
                      ? () => setState(() {
                            _searchQuery = '';
                            _statusFilter = 'all';
                          })
                      : null,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final job = filtered[index];
                  final isSuccess = job.status == 'verified' || job.status == 'uploaded';
                  final isFailed = job.status == 'failed';
                  final statusColor = isSuccess
                      ? AppColors.success
                      : isFailed
                          ? AppColors.error
                          : AppColors.warning;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: AppRadius.card,
                      border: Border.all(
                        color: isFailed ? AppColors.error.withValues(alpha: 0.35) : AppColors.borderSubtle,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status Icon with background
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Icon(
                                isSuccess
                                    ? Icons.check_circle_rounded
                                    : isFailed
                                        ? Icons.error_rounded
                                        : Icons.schedule_rounded,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Track & Metadata Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    job.musicFile?.displayTitle ?? 'Track ID #${job.musicFileId}',
                                    style: AppTypography.h3,
                                  ),
                                  const SizedBox(height: 2),
                                  if (job.musicFile?.artist != null || job.musicFile?.album != null)
                                    Text(
                                      '${job.musicFile?.displayArtist ?? "Unknown Artist"} • ${job.musicFile?.displayAlbum ?? "Unknown Album"}',
                                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                                    ),
                                  if (job.musicFile?.path != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      job.musicFile!.path,
                                      style: AppTypography.caption.copyWith(
                                        fontFamily: 'monospace',
                                        color: AppColors.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (job.ytmEntityId != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.link_rounded, size: 13, color: AppColors.info),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Entity ID: ${job.ytmEntityId}',
                                          style: AppTypography.caption.copyWith(
                                            fontFamily: 'monospace',
                                            color: AppColors.info,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Status Badge & Timestamp
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                AppStatusBadge.fromString(job.status),
                                if (job.completedAt != null || job.startedAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    (job.completedAt ?? job.startedAt ?? '').split('T').join(' ').split('.').first,
                                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),

                        // Error Diagnostics Box
                        if (job.error != null && job.error!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    job.error!,
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
