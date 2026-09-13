import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../shared/widgets/shared_widgets.dart';
import 'components/auth_dialog.dart';
import 'components/folder_browser_dialog.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _headersController = TextEditingController();
  final TextEditingController _folderPathController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  List<String> _folders = [];
  List<RootFolderStats> _folderStats = [];
  AppSettings? _settings;
  ConnectionStatus? _authStatus;
  AuthState _authState = AuthState.disconnected;
  Timer? _authPollTimer;
  String? _currentSessionId;
  bool _isLoading = true;
  bool _isSavingAuth = false;
  String? _authMessage;
  String? _currentAuthUrl;

  List<User> _users = [];
  bool _isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = apiService.apiKey ?? '';
    _loadAll();
  }

  @override
  void dispose() {
    _authPollTimer?.cancel();
    _headersController.dispose();
    _folderPathController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (apiService.currentUser?.isAdmin != true) return;
    setState(() => _isLoadingUsers = true);
    try {
      final users = await apiService.getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final folders = await apiService.getFolders();
      final stats = await apiService.fetchFolderStats();
      final settings = await apiService.getSettings();
      final authStatus = await apiService.fetchAuthStatus();
      try {
        await apiService.fetchCurrentUser();
        await apiService.fetchYtmAccount();
      } catch (_) {}
      if (apiService.currentUser?.isAdmin == true) {
        try {
          _users = await apiService.getUsers();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _folders = folders;
          _folderStats = stats;
          _settings = settings;
          _authStatus = authStatus;
          if (authStatus.connected) {
            _authState = AuthState.connected;
          } else if (!_authState.isConnecting) {
            _authState = AuthState.disconnected;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openFolderBrowser() async {
    final selectedPath = await FolderBrowserDialog.show(
      context,
      initialPath: _folders.isNotEmpty ? _folders.first : '/music',
    );
    if (selectedPath != null && selectedPath.isNotEmpty && !_folders.contains(selectedPath)) {
      final updated = List<String>.from(_folders)..add(selectedPath);
      await apiService.updateFolders(updated);
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added root folder: $selectedPath'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _addManualFolder() async {
    final path = _folderPathController.text.trim();
    if (path.isNotEmpty && !_folders.contains(path)) {
      final updated = List<String>.from(_folders)..add(path);
      await apiService.updateFolders(updated);
      _folderPathController.clear();
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added root folder: $path'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _removeFolder(String folder) async {
    final updated = List<String>.from(_folders)..remove(folder);
    await apiService.updateFolders(updated);
    await _loadAll();
  }

  Future<void> _scanFolder(String folder) async {
    try {
      await apiService.triggerScan([folder]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Started scan for $folder'), backgroundColor: AppColors.surfaceElevated),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _startBrowserAuth() async {
    setState(() {
      _authState = AuthState.starting;
      _authMessage = null;
      _currentAuthUrl = null;
    });

    try {
      final session = await apiService.startAuth(
        originUrl: kIsWeb ? Uri.base.origin : null,
      );
      _currentSessionId = session.sessionId;
      _currentAuthUrl = session.authUrl;

      if (!mounted) return;

      final rawUrl = session.authUrl.trim();
      if (rawUrl.isEmpty) {
        throw const FormatException('Empty authentication URL received from server.');
      }
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('Invalid authentication URL scheme.');
      }

      setState(() {
        _authState = AuthState.waitingForBrowser;
      });

      bool launched = false;
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
      } catch (launchErr, st) {
        debugPrint('url_launcher failed with exception: ${launchErr.runtimeType}\n$st');
        launched = false;
      }

      if (!launched) {
        if (!mounted) return;
        setState(() {
          _authState = AuthState.failed;
          _authMessage = 'Unable to open authentication page. Please check your browser popup blocker or try again.';
        });
        return;
      }

      _startAuthPolling(session.sessionId);
    } catch (e, st) {
      debugPrint('Failed to start authentication session: ${e.runtimeType}\n$st');
      if (mounted) {
        setState(() {
          _authState = AuthState.failed;
          String userMsg = 'Unable to open the YouTube Music authentication page. Please try again.';
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('network') ||
              errStr.contains('connection') ||
              errStr.contains('socket') ||
              errStr.contains('failed to start auth session')) {
            userMsg = 'Unable to connect to the authentication server. Please check your network and try again.';
          } else if (errStr.contains('unapproved origin') || errStr.contains('invalid origin')) {
            userMsg = 'Origin URL validation failed. Please contact your administrator.';
          } else if (errStr.contains('format') || errStr.contains('empty') || errStr.contains('scheme')) {
            userMsg = 'Invalid authentication URL received from server.';
          }
          _authMessage = userMsg;
        });
      }
    }
  }

  void _startAuthPolling(String sessionId) {
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final session = await apiService.getAuthSession(sessionId);
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (session.status == AuthState.connected || session.connected) {
          timer.cancel();
          setState(() {
            _authState = AuthState.connected;
            _authStatus = ConnectionStatus(
              connected: true,
              message: 'Connected to YouTube Music successfully.',
              userName: session.userName,
            );
            _authMessage = null;
            _currentAuthUrl = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to YouTube Music as ${session.userName ?? "account"}'),
              backgroundColor: AppColors.success,
            ),
          );
        } else if (session.status == AuthState.failed) {
          timer.cancel();
          String failureMsg = 'Authentication completed, but the session could not be established.';
          final err = (session.errorMessage ?? '').toLowerCase();
          if (err.contains('reject') ||
              err.contains('denied') ||
              err.contains('permission') ||
              err.contains('unauthorized')) {
            failureMsg = 'YouTube Music authentication was rejected.';
          } else if (session.errorMessage != null && session.errorMessage!.trim().isNotEmpty) {
            failureMsg = session.errorMessage!;
          }
          setState(() {
            _authState = AuthState.failed;
            _authMessage = failureMsg;
            _currentAuthUrl = null;
          });
        } else if (session.status == AuthState.expired) {
          timer.cancel();
          setState(() {
            _authState = AuthState.expired;
            _authMessage = 'Authentication session expired. Please try again.';
            _currentAuthUrl = null;
          });
        } else if (session.status == AuthState.cancelled) {
          timer.cancel();
          setState(() {
            _authState = AuthState.cancelled;
            _authMessage = 'YouTube Music authentication was cancelled.';
            _currentAuthUrl = null;
          });
        } else {
          setState(() {
            _authState = session.status;
          });
        }
      } catch (_) {
        // Keep polling
      }
    });
  }

  Future<void> _cancelAuth() async {
    _authPollTimer?.cancel();
    if (_currentSessionId != null) {
      try {
        await apiService.cancelAuthSession(_currentSessionId!);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _authState = AuthState.cancelled;
        _authMessage = 'YouTube Music authentication was cancelled.';
        _currentAuthUrl = null;
      });
    }
  }

  Future<void> _disconnectAuth() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: const Text('Disconnect YouTube Music?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to disconnect? Stored credentials will be safely removed from your server.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final status = await apiService.disconnectAuth();
      if (mounted) {
        setState(() {
          _authStatus = status;
          _authState = AuthState.disconnected;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('YouTube Music account disconnected.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _submitAuthHeaders() async {
    final raw = _headersController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isSavingAuth = true;
      _authMessage = null;
    });

    try {
      final status = await apiService.setupAuth(raw);
      if (mounted) {
        setState(() {
          _authStatus = status;
          _isSavingAuth = false;
          _headersController.clear();
          _authMessage = status.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status.connected ? 'YouTube Music connected successfully!' : status.message),
            backgroundColor: status.connected ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSavingAuth = false;
          _authMessage = 'Failed: $e';
        });
      }
    }
  }

  Future<void> _testConnection() async {
    try {
      final status = await apiService.testAuth();
      if (mounted) {
        setState(() {
          _authStatus = status;
          if (!status.connected) {
            _authMessage = status.message;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status.message),
            backgroundColor: status.connected ? AppColors.success : AppColors.error,
            action: status.connected
                ? null
                : SnackBarAction(
                    label: 'Fix Connection',
                    textColor: Colors.white,
                    onPressed: _startBrowserAuth,
                  ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authMessage = 'Connection test failed: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test error: $e'),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Fix Connection',
              textColor: Colors.white,
              onPressed: _startBrowserAuth,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: AppLoadingState(message: 'Loading settings & configuration...'));
    }

    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const AppPageHeader(
              title: 'Settings & Configuration',
              kicker: 'SYSTEM PREFERENCES',
              subtitle: 'Manage authentication, music roots, sync intervals, and multi-user access',
            ),
            const SizedBox(height: AppSpacing.lg),

            // User Session Card
            _buildUserProfileCard(),
            const SizedBox(height: AppSpacing.lg),

            // Admin User Accounts Management (visible to Admins)
            if (apiService.currentUser?.isAdmin == true) ...[
              _buildAdminUserManagementCard(),
              const SizedBox(height: AppSpacing.lg),
            ],

            // API Security Section
            _buildCard(
              title: 'API Authentication & Security',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Red Music Locker protects all API endpoints with an API key. '
                    'The key is stored in config/auth/api_key.txt or defined via RED_MUSIC_LOCKER_API_KEY (or YTM_SYNC_API_KEY).',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Enter API Key',
                            labelText: 'API Key',
                            isDense: true,
                            border: const OutlineInputBorder(borderRadius: AppRadius.button),
                            filled: true,
                            fillColor: AppColors.surfaceElevated,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                        onPressed: () async {
                          final key = _apiKeyController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          await apiService.setApiKey(key);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('API Key saved'), backgroundColor: AppColors.surfaceElevated),
                          );
                          _loadAll();
                        },
                        icon: const Icon(Icons.key, size: 16),
                        label: const Text('Save Key'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 1. YouTube Music Auth Section
            _buildYouTubeMusicConnectionCard(),
            const SizedBox(height: AppSpacing.lg),

            // 2. Root Folders Section (Radarr-Style)
            _buildCard(
              title: '2. Root Folders',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Container directories containing your music libraries. Scanned for audio files (.mp3, .flac, .m4a, .ogg, .wma).',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  if (_folderStats.isEmpty && _folders.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Text(
                        'No root folders configured yet. Click "Add Root Folder" to select a folder inside the container (e.g. /music).',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textMuted),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(3.5),
                          1: FlexColumnWidth(1.5),
                          2: FlexColumnWidth(1.2),
                          3: FlexColumnWidth(1.8),
                          4: FixedColumnWidth(96),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          // Header Row
                          TableRow(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: AppColors.divider)),
                            ),
                            children: [
                              _buildTableHeader('Path'),
                              _buildTableHeader('Free Space'),
                              _buildTableHeader('Songs'),
                              _buildTableHeader('Unmapped Folders'),
                              _buildTableHeader('Actions'),
                            ],
                          ),
                          // Data Rows
                          ...(_folderStats.isNotEmpty
                              ? _folderStats
                              : _folders.map((f) => RootFolderStats(
                                    path: f,
                                    exists: true,
                                    freeSpace: 'N/A',
                                    totalSpace: 'N/A',
                                    songsCount: 0,
                                    unmappedCount: 0,
                                  ))).map((stat) => TableRow(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Icon(
                                          stat.exists ? Icons.folder : Icons.folder_off_outlined,
                                          size: 18,
                                          color: stat.exists ? AppColors.info : AppColors.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            stat.path,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: stat.exists ? AppColors.info : AppColors.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Text(
                                      stat.freeSpace,
                                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppColors.textPrimary),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Text(
                                      '${stat.songsCount}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: stat.unmappedCount > 0
                                                ? AppColors.warningBg
                                                : AppColors.successBg,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${stat.unmappedCount}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: stat.unmappedCount > 0 ? AppColors.warning : AppColors.success,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.sync, size: 18, color: AppColors.textMuted),
                                          tooltip: 'Scan this root folder',
                                          onPressed: () => _scanFolder(stat.path),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                          tooltip: 'Remove root folder',
                                          onPressed: () => _removeFolder(stat.path),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Button row: [Add Root Folder] + manual path input
                  Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                        onPressed: _openFolderBrowser,
                        icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                        label: const Text('Add Root Folder', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _folderPathController,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Or enter container path manually (e.g. /music)...',
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surfaceElevated,
                            border: OutlineInputBorder(
                              borderRadius: AppRadius.button,
                              borderSide: BorderSide(color: AppColors.borderSubtle),
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _addManualFolder(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          foregroundColor: AppColors.textPrimary,
                          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                        onPressed: _addManualFolder,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 3. Sync Preferences
            _buildCard(
              title: '3. Synchronization Preferences',
              child: Column(
                children: [
                  SwitchListTile(
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Verify Uploads Post-Upload', style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      'Refreshes your YouTube Music library and confirms track existence before marking as verified.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    value: _settings?.verifyUploads ?? true,
                    onChanged: (val) async {
                      await apiService.updateSettings(verifyUploads: val);
                      setState(() => _settings = AppSettings(
                        musicFolders: _settings!.musicFolders,
                        autoUpload: _settings!.autoUpload,
                        scanIntervalMinutes: _settings!.scanIntervalMinutes,
                        verifyUploads: val,
                      ));
                    },
                  ),
                  const Divider(color: AppColors.divider),
                  SwitchListTile(
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatically Upload New Music', style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      'Automatically queue and upload newly detected files during periodic background scans (defaults to OFF).',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    value: _settings?.autoUpload ?? false,
                    onChanged: (val) async {
                      await apiService.updateSettings(autoUpload: val);
                      setState(() => _settings = AppSettings(
                        musicFolders: _settings!.musicFolders,
                        autoUpload: val,
                        scanIntervalMinutes: _settings!.scanIntervalMinutes,
                        verifyUploads: _settings!.verifyUploads,
                      ));
                    },
                  ),
                  const Divider(color: AppColors.divider),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Periodic Scan Interval', style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      'How frequently local folders are rescanned for new music additions.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    trailing: DropdownButton<int>(
                      value: _settings?.scanIntervalMinutes ?? 15,
                      dropdownColor: AppColors.surfaceElevated,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 5, child: Text('5 minutes')),
                        DropdownMenuItem(value: 15, child: Text('15 minutes')),
                        DropdownMenuItem(value: 30, child: Text('30 minutes')),
                        DropdownMenuItem(value: 60, child: Text('1 hour')),
                      ],
                      onChanged: (val) async {
                        if (val != null) {
                          await apiService.updateSettings(scanIntervalMinutes: val);
                          setState(() => _settings = AppSettings(
                            musicFolders: _settings!.musicFolders,
                            autoUpload: _settings!.autoUpload,
                            scanIntervalMinutes: val,
                            verifyUploads: _settings!.verifyUploads,
                          ));
                        }
                      },
                    ),
                  ),
                  const Divider(color: AppColors.divider),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sequential Uploads (One at a Time)', style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      'Strictly enforced for stability and avoiding YouTube Music rate limit blocks.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    trailing: const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 4. Database Maintenance & Backup
            _buildCard(
              title: '4. Database Maintenance & Backup',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create timestamped point-in-time backups of your local tracks, matches, and upload metadata.',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceElevated,
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderSubtle),
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final path = await apiService.backupDatabase();
                        messenger.showSnackBar(
                          SnackBar(content: Text('Backup created: $path'), backgroundColor: AppColors.success),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Backup failed: $e'), backgroundColor: AppColors.error),
                        );
                      }
                    },
                    icon: const Icon(Icons.backup, size: 16),
                    label: const Text('Create Database Backup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYouTubeMusicConnectionCard() {
    final isConnected = _authState == AuthState.connected || (_authStatus?.connected ?? false);
    final isConnecting = _authState.isConnecting;

    return _buildCard(
      title: '1. YouTube Music Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Row with Actions
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 680;
              final statusWidget = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected
                        ? Icons.check_circle
                        : (isConnecting ? Icons.sync : Icons.radio_button_checked),
                    color: isConnected
                        ? AppColors.success
                        : (isConnecting ? AppColors.warning : AppColors.error),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'Connected' : _authState.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isConnected
                          ? AppColors.success
                          : (isConnecting ? AppColors.warning : AppColors.error),
                    ),
                  ),
                  if (isConnected && _authStatus?.userName != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _authStatus!.userName!,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ],
              );

              final actionsWidget = isConnected
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testConnection,
                          icon: const Icon(Icons.network_check, size: 16),
                          label: const Text('Test Connection'),
                          style: OutlinedButton.styleFrom(
                            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                          ),
                        ),
                        Tooltip(
                          message: 'Relink and re-authenticate your YouTube Music account without deleting credentials',
                          child: FilledButton.icon(
                            onPressed: _startBrowserAuth,
                            icon: const Icon(Icons.sync_problem_rounded, size: 16),
                            label: const Text('Fix Connection'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _disconnectAuth,
                          icon: const Icon(Icons.link_off, size: 16, color: AppColors.error),
                          label: const Text('Disconnect', style: TextStyle(color: AppColors.error)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.error),
                            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                          ),
                        ),
                      ],
                    )
                  : null;

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statusWidget,
                    if (actionsWidget != null) ...[
                      const SizedBox(height: 12),
                      actionsWidget,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  statusWidget,
                  const Spacer(),
                  ?actionsWidget,
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Card Body
          if (isConnected) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: AppRadius.card,
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: AppColors.success, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _authStatus?.userName ?? 'YouTube Music Account Linked',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your account is authorized to synchronize library uploads and playlists. Credentials are encrypted and stored safely on your server.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: 'Refresh YouTube Music authentication session without disconnecting',
                    child: OutlinedButton.icon(
                      onPressed: _startBrowserAuth,
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Relink'),
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_authStatus != null && !_authStatus!.connected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _authStatus!.message.isNotEmpty
                            ? _authStatus!.message
                            : 'Connection test failed. Please fix connection or relink your account.',
                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _startBrowserAuth,
                      icon: const Icon(Icons.sync_problem_rounded, size: 16),
                      label: const Text('Fix Connection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (isConnecting) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: AppRadius.card,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _authState == AuthState.starting
                              ? 'Starting connection session...'
                              : _authState == AuthState.waitingForBrowser
                                  ? 'Waiting for browser authorization...'
                                  : 'Verifying connection with YouTube Music...',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning),
                        ),
                      ),
                      TextButton(
                        onPressed: _cancelAuth,
                        child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Sign in to YouTube Music in the browser tab that just opened.\n'
                    '2. The companion extension will automatically capture your session authorization and link your account.\n'
                    '3. Return here once complete.',
                    style: TextStyle(color: Colors.grey[300], fontSize: 12, height: 1.4),
                  ),
                  if (_currentAuthUrl != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final raw = _currentAuthUrl;
                        if (raw != null) {
                          final uri = Uri.tryParse(raw);
                          if (uri != null) {
                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.platformDefault,
                                webOnlyWindowName: '_blank',
                              );
                            } catch (_) {}
                          }
                        }
                      },
                      child: const Text(
                        "Didn't open? Click here to open YouTube Music.",
                        style: TextStyle(
                          color: AppColors.info,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Disconnected / Failed / Cancelled / Expired
            if (_authState.canRetry || _authMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline, size: 20, color: AppColors.error),
                        SizedBox(width: 10),
                        Text(
                          "We couldn't connect your YouTube Music account.",
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 14),
                        ),
                      ],
                    ),
                    if (_authMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _authMessage!,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _startBrowserAuth,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Connect your YouTube Music account to synchronize your uploads and playlists.\n'
                'Your music stays on your server, and your password is never stored by Red Music Locker.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _startBrowserAuth,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect YouTube Music', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),

          // Advanced / Developer Options (Accordion)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Advanced / Developer Authentication',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              subtitle: const Text(
                'For developers and troubleshooting only (manual header input)',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: AppRadius.card,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Directly supply raw session authorization headers for headless environments or manual configuration:',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _headersController,
                        maxLines: 4,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'cookie: ...\nauthorization: SAPISIDHASH ...',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          border: const OutlineInputBorder(borderRadius: AppRadius.button),
                          filled: true,
                          fillColor: AppColors.surfaceSubtle,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _isSavingAuth ? null : _submitAuthHeaders,
                        icon: _isSavingAuth
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.code, size: 16),
                        label: const Text('Save Manual Headers'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceSubtle,
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.borderSubtle),
                          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Material(
      color: AppColors.surfaceSubtle,
      borderRadius: AppRadius.card,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.h2),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfileCard() {
    final user = apiService.currentUser;
    final ytmAccount = apiService.ytmAccount;

    return _buildCard(
      title: 'Current User Session',
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: (user?.isAdmin ?? false) ? AppColors.primary : AppColors.info,
            child: Text(
              user?.username.isNotEmpty == true ? user!.username[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      user?.username ?? 'Not Signed In',
                      style: AppTypography.h3,
                    ),
                    if (user != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: user.isAdmin ? AppColors.primaryMuted : AppColors.infoBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          user.role,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: user.isAdmin ? AppColors.primaryLight : AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user != null
                      ? 'ID: ${user.id} • YTM Account: ${ytmAccount?.accountName ?? (ytmAccount?.isConnected == true ? "Connected" : "Disconnected")}'
                      : 'Authenticate with a username & password or master API key to access features.',
                  style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderSubtle),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            onPressed: () async {
              final loggedIn = await AuthDialog.show(context);
              if (loggedIn == true && mounted) {
                _loadAll();
              }
            },
            icon: const Icon(Icons.switch_account, size: 16),
            label: Text(user == null ? 'Sign In' : 'Switch Account'),
          ),
          if (user != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await apiService.logout();
                if (mounted) {
                  _loadAll();
                }
              },
              icon: const Icon(Icons.logout, size: 16, color: AppColors.error),
              label: const Text('Log Out', style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.borderSubtle),
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminUserManagementCard() {
    return _buildCard(
      title: 'Administrator: User Accounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Manage application accounts and access permissions.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              ),
              ElevatedButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingUsers)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            Text('No users found.', style: AppTypography.bodySm.copyWith(color: AppColors.textMuted))
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.5),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text('Username', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text('Actions', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                  ],
                ),
                ..._users.map((u) {
                  final isCurrent = u.id == apiService.currentUser?.id;
                  return TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 16, color: u.isAdmin ? AppColors.primary : AppColors.info),
                            const SizedBox(width: 8),
                            Text(u.username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                            if (isCurrent) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(4)),
                                child: const Text('You', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(u.role, style: TextStyle(fontSize: 12, color: u.isAdmin ? AppColors.primaryLight : AppColors.info)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Icon(u.isActive ? Icons.check_circle : Icons.cancel, size: 12, color: u.isActive ? AppColors.success : AppColors.error),
                            const SizedBox(width: 4),
                            Text(u.isActive ? 'Active' : 'Disabled', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
                              tooltip: 'Edit User',
                              onPressed: () => _showEditUserDialog(u),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                              tooltip: 'Delete User',
                              onPressed: isCurrent ? null : () => _confirmDeleteUser(u),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showAddUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'USER';
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
          title: const Text('Add New User', style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dialogError != null) ...[
                Text(dialogError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: usernameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Role',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'USER', child: Text('Standard User')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('Administrator')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedRole = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
              ),
              onPressed: () async {
                final uname = usernameController.text.trim();
                final pwd = passwordController.text;
                if (uname.isEmpty || pwd.isEmpty) {
                  setDialogState(() => dialogError = 'Username and password required');
                  return;
                }
                try {
                  await apiService.createUser(uname, pwd, role: selectedRole);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadUsers();
                } catch (e) {
                  setDialogState(() => dialogError = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Create User'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditUserDialog(User user) async {
    final passwordController = TextEditingController();
    String selectedRole = user.role;
    bool isActive = user.isActive;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
          title: Text('Edit User: ${user.username}', style: const TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dialogError != null) ...[
                Text(dialogError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'New Password (leave blank to keep current)',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Role',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'USER', child: Text('Standard User')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('Administrator')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedRole = val);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                activeThumbColor: AppColors.primary,
                title: const Text('Active Account', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                contentPadding: EdgeInsets.zero,
                value: isActive,
                onChanged: (val) => setDialogState(() => isActive = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
              ),
              onPressed: () async {
                try {
                  await apiService.updateUser(
                    user.id,
                    password: passwordController.text.isNotEmpty ? passwordController.text : null,
                    role: selectedRole,
                    isActive: isActive,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadUsers();
                } catch (e) {
                  setDialogState(() => dialogError = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: const Text('Delete User', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to delete user "${user.username}"? All associated data will be removed.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await apiService.deleteUser(user.id);
        await _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User "${user.username}" deleted'), backgroundColor: AppColors.surfaceElevated),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }
}
