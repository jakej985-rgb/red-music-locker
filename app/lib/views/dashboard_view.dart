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

class DashboardView extends StatefulWidget {
  final Function(int) onNavigateTab;

  const DashboardView({super.key, required this.onNavigateTab});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  DashboardStats? _stats;
  List<SyncJob> _recentJobs = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadStats(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final stats = await apiService.fetchDashboardStatus();
      List<SyncJob> jobs = [];
      try {
        final allJobs = await apiService.getHistory();
        jobs = allJobs.take(5).toList();
      } catch (_) {
        // Non-blocking history load
      }

      if (mounted) {
        setState(() {
          _stats = stats;
          _recentJobs = jobs;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Backend daemon offline or unreachable. Verify the service is running on port 8765/6969.';
        });
      }
    }
  }

  Future<void> _triggerScan() async {
    try {
      await apiService.triggerScan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Music folder scan started in background...')),
        );
      }
      _loadStats(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _triggerSync() async {
    try {
      await apiService.triggerSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Library sync started (fetching YTM uploads & matching)...'),
          ),
        );
      }
      _loadStats(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _uploadAllMissing() async {
    try {
      final count = await apiService.uploadAllMissing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enqueued $count missing tracks for upload!')),
        );
        _loadStats(silent: true);
        widget.onNavigateTab(4); // Go to queue view
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _stats == null) {
      return const Center(
        child: AppLoadingState(message: 'Connecting to Red Music Locker daemon...'),
      );
    }

    if (_errorMessage != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppErrorState(
            title: 'Locker Daemon Offline',
            message: _errorMessage!,
            onRetry: () => _loadStats(silent: false),
          ),
        ),
      );
    }

    final stats = _stats!;
    final syncPct = stats.localSongsCount > 0
        ? ((stats.uploadedCount / stats.localSongsCount) * 100).clamp(0, 100).toInt()
        : 100;

    final isMobile = ResponsiveLayout.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          AppPageHeader(
            title: 'MUSIC LOCKER',
            subtitle: stats.ytmConnected
                ? (stats.accountName != null
                    ? 'Connected as ${stats.accountName} • All locker services operational'
                    : 'Personal cloud music locker synchronization and health command center')
                : 'Disconnected • Authentication required to sync personal locker',
            kicker: '${_getGreeting().toUpperCase()} • LOCKER STATUS',
            actions: [
              OutlinedButton.icon(
                onPressed: () => _loadStats(silent: false),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Active Operations Indicator Banner
          if (stats.isScanning || stats.isUploading) ...[
            _buildActiveTaskBanner(stats),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Attention Section (only when action is needed)
          _buildAttentionSection(stats),

          // Primary Actions Command Bar
          _buildActionsBar(stats),
          const SizedBox(height: AppSpacing.xl),

          // Primary Statistics Grid
          AppSectionHeader(
            title: 'Locker Telemetry',
            subtitle: 'Real-time synchronization breakdown across local storage and YouTube Music',
            action: Text(
              '$syncPct% Synced',
              style: AppTypography.label.copyWith(
                color: syncPct >= 90
                    ? AppColors.success
                    : (syncPct >= 50 ? AppColors.warning : AppColors.error),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildStatsGrid(stats, syncPct),
          const SizedBox(height: AppSpacing.xl),

          // Recent Activity Section
          _buildRecentActivitySection(),
        ],
      ),
    );
  }

  Widget _buildActiveTaskBanner(DashboardStats stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              stats.isScanning && stats.isUploading
                  ? 'Scanning local folders and processing upload queue...'
                  : stats.isScanning
                      ? 'Scanning configured local music directories...'
                      : 'Uploading queued music tracks to YouTube Music...',
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionSection(DashboardStats stats) {
    final List<Widget> attentionCards = [];

    if (!stats.ytmConnected) {
      attentionCards.add(
        _buildAttentionCard(
          title: 'YouTube Music Disconnected',
          description:
              'OAuth session is missing or expired. Connect your YouTube Music account to enable syncing.',
          buttonLabel: 'Setup Connection',
          badgeStatus: 'failed',
          onPressed: () => widget.onNavigateTab(6), // Settings
        ),
      );
    }

    if (stats.failedCount > 0) {
      attentionCards.add(
        _buildAttentionCard(
          title: '${stats.failedCount} uploads failed',
          description:
              'Recent upload attempts encountered errors or rate limits. Review failed tracks in history.',
          buttonLabel: 'Review in History',
          badgeStatus: 'error',
          onPressed: () => widget.onNavigateTab(5), // History
        ),
      );
    }

    if (stats.missingCount > 0) {
      attentionCards.add(
        _buildAttentionCard(
          title: '${stats.missingCount} tracks missing from YouTube Music',
          description:
              'Local songs found on disk that have not yet been matched or uploaded to your locker.',
          buttonLabel: 'Upload All Missing',
          badgeStatus: 'missing',
          isPrimary: true,
          onPressed: stats.ytmConnected && !stats.isUploading ? _uploadAllMissing : null,
        ),
      );
    }

    if (attentionCards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 18, color: AppColors.warning),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'ACTION REQUIRED',
                style: AppTypography.label.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Column(
            children: attentionCards
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: card,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionCard({
    required String title,
    required String description,
    required String buttonLabel,
    required String badgeStatus,
    bool isPrimary = false,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppStatusBadge.fromString(badgeStatus),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (isPrimary)
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              child: Text(buttonLabel),
            )
          else
            OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              child: Text(buttonLabel),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsBar(DashboardStats stats) {
    final isMobile = ResponsiveLayout.isMobile(context);

    final syncButton = ElevatedButton.icon(
      onPressed: stats.ytmConnected && !stats.isUploading ? _triggerSync : null,
      icon: stats.isUploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.sync, size: 20),
      label: Text(stats.isUploading ? 'SYNCING...' : 'SYNC NOW'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md + 2,
        ),
        textStyle: AppTypography.label.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );

    final scanButton = OutlinedButton.icon(
      onPressed: stats.isScanning ? null : _triggerScan,
      icon: stats.isScanning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.folder_open, size: 18),
      label: Text(stats.isScanning ? 'Scanning...' : 'Scan Library'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
      ),
    );

    final uploadMissingButton = stats.missingCount > 0
        ? FilledButton.tonalIcon(
            onPressed: stats.ytmConnected && !stats.isUploading ? _uploadAllMissing : null,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text('Upload Missing (${stats.missingCount})'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md + 2,
              ),
            ),
          )
        : null;

    final managePlaylistsButton = OutlinedButton.icon(
      onPressed: () => widget.onNavigateTab(3),
      icon: const Icon(Icons.playlist_play, size: 18),
      label: const Text('Playlists'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          syncButton,
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: scanButton),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: managePlaylistsButton),
            ],
          ),
          if (uploadMissingButton != null) ...[
            const SizedBox(height: AppSpacing.sm),
            uploadMissingButton,
          ],
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        syncButton,
        scanButton,
        ?uploadMissingButton,
        managePlaylistsButton,
      ],
    );
  }

  Widget _buildStatsGrid(DashboardStats stats, int syncPct) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 4;
        if (constraints.maxWidth < 600) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 900) {
          crossAxisCount = 2;
        }

        final cards = [
          AppStatCard(
            title: 'Local Tracks',
            value: '${stats.localSongsCount}',
            subtitle: 'On local disk',
            icon: Icons.library_music_outlined,
            accentColor: AppColors.info,
            onTap: () => widget.onNavigateTab(1),
          ),
          AppStatCard(
            title: 'Uploaded to YTM',
            value: '${stats.uploadedCount}',
            subtitle: '${stats.ytmUploadsCount} total in YTM cloud',
            icon: Icons.cloud_done_outlined,
            accentColor: AppColors.success,
            onTap: () => widget.onNavigateTab(2),
          ),
          AppStatCard(
            title: 'Missing from YTM',
            value: '${stats.missingCount}',
            subtitle: stats.missingCount > 0 ? 'Requires upload' : 'All songs matched',
            icon: Icons.cloud_upload_outlined,
            accentColor: stats.missingCount > 0 ? AppColors.warning : AppColors.success,
            onTap: () => widget.onNavigateTab(1),
          ),
          AppStatCard(
            title: 'Locker Sync Rate',
            value: '$syncPct%',
            subtitle: stats.inQueueCount > 0 ? '${stats.inQueueCount} in upload queue' : 'Fully synchronized',
            icon: Icons.sync,
            accentColor: syncPct >= 90
                ? AppColors.success
                : (syncPct >= 50 ? AppColors.warning : AppColors.error),
            onTap: () => widget.onNavigateTab(4),
          ),
        ];

        if (crossAxisCount == 1) {
          return Column(
            children: cards
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: card,
                    ))
                .toList(),
          );
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: crossAxisCount == 4 ? 2.1 : 2.4,
          children: cards,
        );
      },
    );
  }

  Widget _buildRecentActivitySection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent Activity', style: AppTypography.h3),
                  const SizedBox(height: 2),
                  Text(
                    'Latest background synchronization events',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => widget.onNavigateTab(5), // History
                icon: const Icon(Icons.arrow_forward, size: 14),
                label: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_recentJobs.isEmpty)
            const AppEmptyState(
              icon: Icons.history,
              title: 'No Recent Activity',
              description:
                  'Trigger a sync or upload tracks to monitor your live activity timeline here.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentJobs.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: AppColors.borderSubtle, height: 16),
              itemBuilder: (context, index) {
                final job = _recentJobs[index];
                final trackTitle = job.musicFile?.title ?? 'Track #${job.musicFileId}';
                final trackArtist = job.musicFile?.artist ?? 'Unknown Artist';
                final time = job.completedAt ?? job.startedAt ?? 'Pending';

                return Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.rSm,
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const Icon(
                        Icons.music_note,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trackTitle,
                            style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$trackArtist • $time',
                            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    AppStatusBadge.fromString(job.status),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
