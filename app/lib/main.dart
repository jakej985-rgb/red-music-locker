import 'dart:async';
import 'package:flutter/material.dart';

import 'core/navigation/account_indicator.dart';
import 'core/navigation/sync_status_indicator.dart';
import 'core/responsive/responsive_layout.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_radius.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_typography.dart';
import 'models/models.dart';
import 'services/api_service.dart';
import 'views/components/auth_dialog.dart';
import 'views/dashboard_view.dart';
import 'views/family_view.dart';
import 'views/history_view.dart';
import 'views/library_view.dart';
import 'views/playlists_view.dart';
import 'views/queue_view.dart';
import 'views/settings_view.dart';
import 'views/uploads_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await apiService.initApiKey();
  runApp(const YTMSyncApp());
}

class YTMSyncApp extends StatelessWidget {
  const YTMSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Red Music Locker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _isAuthDialogOpen = false;
  DashboardStats? _dashboardStats;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    apiService.onUnauthorized = _showAuthDialog;
    _refreshStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final stats = await apiService.fetchDashboardStatus();
      if (mounted) {
        setState(() {
          _dashboardStats = stats;
        });
      }
    } catch (_) {
      // Non-blocking background status refresh
    }
  }

  void _showAuthDialog() {
    if (_isAuthDialogOpen || !mounted) return;
    _isAuthDialogOpen = true;
    AuthDialog.show(context).then((_) {
      _isAuthDialogOpen = false;
      if (mounted) {
        _refreshStatus();
        setState(() {});
      }
    });
  }

  void _navigateToTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showMobileMoreSheet(BuildContext context) {
    final pendingCount = _dashboardStats?.inQueueCount ?? 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  'More Views',
                  style: AppTypography.h3.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: const Icon(Icons.queue_music_outlined, color: AppColors.textPrimary),
                title: const Text('Queue'),
                trailing: pendingCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warningBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$pendingCount',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                selected: _selectedIndex == 4,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToTab(4);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_outlined, color: AppColors.textPrimary),
                title: const Text('Sync History'),
                selected: _selectedIndex == 5,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToTab(5);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
                title: const Text('Settings'),
                selected: _selectedIndex == 6,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToTab(6);
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline, color: AppColors.textPrimary),
                title: const Text('Family Mode'),
                selected: _selectedIndex == 7,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToTab(7);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.input,
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: AppRadius.input,
                ),
                child: const Icon(Icons.music_note, color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RED MUSIC LOCKER',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Cloud Music Sync & Locker',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final views = [
      DashboardView(onNavigateTab: _navigateToTab),
      const LibraryView(),
      const UploadsView(),
      const PlaylistsView(),
      const QueueView(),
      const HistoryView(),
      const SettingsView(),
      FamilyView(onNavigateTab: _navigateToTab),
    ];

    final isMobile = ResponsiveLayout.isMobile(context);
    final pendingCount = _dashboardStats?.inQueueCount ?? 0;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: AppSpacing.md,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 24,
                    height: 24,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Flexible(
                child: Text(
                  'RED MUSIC LOCKER',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            AppSyncStatusIndicator(
              stats: _dashboardStats,
              compact: true,
              onTap: () => _navigateToTab(4),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppAccountIndicator(
              compact: true,
              onSignIn: _showAuthDialog,
              onNavigateTab: _navigateToTab,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: views,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex < 4 ? _selectedIndex : 4,
          onDestinationSelected: (int index) {
            if (index == 4) {
              _showMobileMoreSheet(context);
            } else {
              _navigateToTab(index);
            }
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
              label: 'Dashboard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music, color: AppColors.primary),
              label: 'Library',
            ),
            const NavigationDestination(
              icon: Icon(Icons.cloud_done_outlined),
              selectedIcon: Icon(Icons.cloud_done, color: AppColors.primary),
              label: 'Uploads',
            ),
            const NavigationDestination(
              icon: Icon(Icons.playlist_play_outlined),
              selectedIcon: Icon(Icons.playlist_play, color: AppColors.primary),
              label: 'Playlists',
            ),
            NavigationDestination(
              icon: pendingCount > 0
                  ? Badge(
                      label: Text('$pendingCount'),
                      backgroundColor: AppColors.warning,
                      child: const Icon(Icons.more_horiz),
                    )
                  : const Icon(Icons.more_horiz),
              selectedIcon: const Icon(Icons.more_horiz, color: AppColors.primary),
              label: 'More',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Navigation Rail
          NavigationRail(
            backgroundColor: AppColors.surface,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            extended: true,
            minExtendedWidth: 220,
            leading: _buildLogoHeader(),
            trailing: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAccountIndicator(
                    onSignIn: _showAuthDialog,
                    onNavigateTab: _navigateToTab,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppSyncStatusIndicator(
                    stats: _dashboardStats,
                    onTap: () => _navigateToTab(4),
                  ),
                ],
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
                label: Text('Dashboard'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music, color: AppColors.primary),
                label: Text('Music Library'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.cloud_done_outlined),
                selectedIcon: Icon(Icons.cloud_done, color: AppColors.primary),
                label: Text('YTM Uploads'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.playlist_play_outlined),
                selectedIcon: Icon(Icons.playlist_play, color: AppColors.primary),
                label: Text('YTM Playlists'),
              ),
              NavigationRailDestination(
                icon: pendingCount > 0
                    ? Badge(
                        label: Text('$pendingCount'),
                        backgroundColor: AppColors.warning,
                        child: const Icon(Icons.queue_music_outlined),
                      )
                    : const Icon(Icons.queue_music_outlined),
                selectedIcon: pendingCount > 0
                    ? Badge(
                        label: Text('$pendingCount'),
                        backgroundColor: AppColors.warning,
                        child: const Icon(Icons.queue_music, color: AppColors.primary),
                      )
                    : const Icon(Icons.queue_music, color: AppColors.primary),
                label: const Text('Queue'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history, color: AppColors.primary),
                label: Text('Sync History'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppColors.primary),
                label: Text('Settings'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people, color: AppColors.primary),
                label: Text('Family Mode'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: AppColors.divider),

          // Main View Content
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: views,
            ),
          ),
        ],
      ),
    );
  }
}
