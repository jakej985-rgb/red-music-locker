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

class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key});

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  List<YTMPlaylist> _playlists = [];
  bool _isLoading = false;
  String? _errorMessage;

  YTMPlaylist? _selectedPlaylist;
  YTMPlaylistDetails? _playlistDetails;
  bool _isLoadingDetails = false;
  String? _detailsErrorMessage;

  String _searchQuery = '';
  String _trackFilter = 'all'; // 'all', 'local', 'uploads', 'missing'

  Timer? _syncPollTimer;
  PlaylistSyncStatusModel? _syncStatus;
  final Set<String> _downloadingVideoIds = {};

  List<ReplicatedPlaylistModel> _replicatedPlaylists = [];

  ReplicatedPlaylistModel? get _currentReplicaConfig {
    if (_selectedPlaylist == null) return null;
    try {
      return _replicatedPlaylists.firstWhere((r) => r.sourcePlaylistId == _selectedPlaylist!.id);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
    _loadReplicatedPlaylists();
    _checkInitialSyncStatus();
  }

  @override
  void dispose() {
    _syncPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialSyncStatus() async {
    try {
      final status = await apiService.getPlaylistSyncStatus();
      if (mounted && status.isRunning) {
        setState(() => _syncStatus = status);
        _startSyncPolling();
      }
    } catch (_) {}
  }

  void _startSyncPolling() {
    _syncPollTimer?.cancel();
    _syncPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final status = await apiService.getPlaylistSyncStatus();
        if (mounted) {
          setState(() => _syncStatus = status);
          if (!status.isRunning) {
            _stopSyncPolling();
            if (_selectedPlaylist != null) {
              _selectPlaylist(_selectedPlaylist!);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Playlist sync completed: ${status.completedTracks} uploaded, ${status.failedTracks} failed.'),
                backgroundColor: status.failedTracks > 0 ? Colors.amber[800] : Colors.green,
              ),
            );
          }
        }
      } catch (_) {}
    });
  }

  void _stopSyncPolling() {
    _syncPollTimer?.cancel();
    _syncPollTimer = null;
  }

  Future<void> _loadReplicatedPlaylists() async {
    try {
      final list = await apiService.fetchReplicatedPlaylists();
      if (mounted) {
        setState(() => _replicatedPlaylists = list);
      }
    } catch (_) {}
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _loadReplicatedPlaylists();

    try {
      final list = await apiService.fetchPlaylists();
      if (mounted) {
        setState(() {
          _playlists = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectPlaylist(YTMPlaylist playlist, {bool refresh = false}) async {
    setState(() {
      _selectedPlaylist = playlist;
      _isLoadingDetails = true;
      _detailsErrorMessage = null;
      _trackFilter = 'all';
    });

    try {
      final details = await apiService.fetchPlaylistDetails(playlist.id, refresh: refresh);
      if (mounted) {
        setState(() {
          _playlistDetails = details;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailsErrorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<void> _syncMissingTracks() async {
    if (_selectedPlaylist == null) return;

    List<SelectableAccountItem> accounts = [];
    try {
      accounts = await apiService.getSelectableAccounts();
    } catch (_) {}

    final permitted = accounts.where((a) => a.ytmConnected && (a.isSelf || a.allowFamilyUploads || a.allowFamilySync)).toList();
    List<String> targetUserIds = [];

    if (permitted.length > 1 && mounted) {
      final selected = Set<String>.from(permitted.map((a) => a.userId));
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E28),
            title: const Row(
              children: [
                Icon(Icons.family_restroom, color: Color(0xFF8A2387)),
                SizedBox(width: 10),
                Text('Upload Missing Tracks to Family'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select which accounts should receive the uploaded songs in their cloud locker:',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14141B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: permitted.map((acc) {
                        final isChecked = selected.contains(acc.userId);
                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          activeColor: const Color(0xFF8A2387),
                          title: Row(
                            children: [
                              Text(acc.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              if (acc.accountName != null && acc.accountName!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text('(${acc.accountName})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                              if (acc.isSelf) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          onChanged: (val) {
                            setDlgState(() {
                              if (val == true) {
                                selected.add(acc.userId);
                              } else if (selected.length > 1) {
                                selected.remove(acc.userId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_upload, size: 16),
                label: const Text('Start Upload Sync'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A2387),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;
      targetUserIds = selected.toList();
    }

    try {
      final res = await apiService.syncMissingPlaylistTracks(
        _selectedPlaylist!.id,
        destinationUserIds: targetUserIds.isNotEmpty ? targetUserIds : null,
      );
      final queued = res['queued'] as int? ?? 0;
      if (mounted) {
        if (queued > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Started background sync for $queued missing tracks across selected accounts!'),
              backgroundColor: const Color(0xFF8A2387),
            ),
          );
          _startSyncPolling();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All tracks are already uploaded for the selected accounts!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndUploadSingleTrack(YTMPlaylistTrack track) async {
    if (track.videoId == null) return;
    setState(() {
      _downloadingVideoIds.add(track.videoId!);
    });

    try {
      final res = await apiService.downloadAndUploadPlaylistTrack({
        'video_id': track.videoId,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'thumbnail': track.thumbnail,
        'enrich_metadata': true,
      });

      if (mounted) {
        setState(() {
          _downloadingVideoIds.remove(track.videoId);
          if (_playlistDetails != null) {
            final idx = _playlistDetails!.tracks.indexWhere((t) => t.videoId == track.videoId);
            if (idx != -1) {
              final updated = _playlistDetails!.tracks[idx].copyWith(
                inUploads: true,
                inLocal: res['local_path'] != null ? true : null,
                localPath: res['local_path'] as String?,
              );
              _playlistDetails!.tracks[idx] = updated;
            }
          }
        });

        final alreadyEx = res['already_exists'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alreadyEx
                ? '"${track.title}" is already in your YouTube Music locker!'
                : 'Downloaded, tagged, and uploaded "${track.title}" to YouTube Music!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingVideoIds.remove(track.videoId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showImportPlaylistDialog() async {
    final controller = TextEditingController();
    bool isImporting = false;
    String? importError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E28),
          title: const Row(
            children: [
              Icon(Icons.link, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('Import YouTube Playlist'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter any YouTube or YouTube Music playlist URL (public or unlisted) to audit and download missing tracks.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                enabled: !isImporting,
                decoration: const InputDecoration(
                  hintText: 'https://www.youtube.com/playlist?list=...',
                  prefixIcon: Icon(Icons.playlist_play),
                  border: OutlineInputBorder(),
                ),
              ),
              if (isImporting) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Extracting playlist tracks via yt-dlp...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ],
                ),
              ],
              if (importError != null) ...[
                const SizedBox(height: 12),
                Text(importError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isImporting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isImporting ? null : () async {
                final url = controller.text.trim();
                if (url.isEmpty) return;
                setDialogState(() {
                  isImporting = true;
                  importError = null;
                });
                try {
                  final details = await apiService.importPlaylistUrl(url);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {
                      _selectedPlaylist = YTMPlaylist(
                        id: details.id,
                        title: details.title,
                        description: details.description,
                        trackCount: details.trackCount,
                        thumbnail: details.thumbnail,
                      );
                      _playlistDetails = details;
                      _isLoadingDetails = false;
                      _trackFilter = 'all';
                    });
                  }
                } catch (e) {
                  setDialogState(() {
                    isImporting = false;
                    importError = e.toString().replaceFirst('Exception: ', '');
                  });
                }
              },
              child: const Text('Import & Audit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAllReplicasDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        title: const Row(
          children: [
            Icon(Icons.sync_alt, color: Colors.tealAccent),
            SizedBox(width: 10),
            Text('Active Locker Replicas'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: _replicatedPlaylists.isEmpty
              ? const Text('No active replicas configured yet.', style: TextStyle(color: Colors.grey))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _replicatedPlaylists.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                  itemBuilder: (ctx, idx) {
                    final r = _replicatedPlaylists[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.queue_music, color: Colors.tealAccent),
                      title: Text(r.sourcePlaylistName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Replica: ${r.destinationPlaylistName}', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openReplicationModal(r);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: const Text('Manage', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateReplicaDialog(YTMPlaylist playlist) async {
    final destNameController = TextEditingController(text: '${playlist.title} - Locker');
    bool isCreating = false;
    String? errorMsg;

    List<SelectableAccountItem> accounts = [];
    try {
      accounts = await apiService.getSelectableAccounts();
    } catch (_) {}

    final permittedAccounts = accounts.where((a) => a.ytmConnected && (a.isSelf || a.allowFamilyPlaylists)).toList();
    final Set<String> selectedUserIds = {};
    for (final a in permittedAccounts) {
      if (a.isSelf) selectedUserIds.add(a.userId);
    }
    if (selectedUserIds.isEmpty && permittedAccounts.isNotEmpty) {
      selectedUserIds.add(permittedAccounts.first.userId);
    }

    bool uploadMissingToTargets = true;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E28),
          title: const Row(
            children: [
              Icon(Icons.copy_all, color: Color(0xFF0288D1)),
              SizedBox(width: 10),
              Text('Create 1:1 Locker Replica'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0288D1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0288D1).withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Creates an automated YouTube Music playlist containing ONLY songs verified in your Upload Locker, in exact 1:1 source order.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Source Playlist', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  playlist.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('Destination Replica Name', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: destNameController,
                  enabled: !isCreating,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.queue_music),
                  ),
                ),
                if (permittedAccounts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.family_restroom, size: 16, color: Colors.purpleAccent),
                      SizedBox(width: 6),
                      Text('Target Accounts (Upload & Replicate to)', style: TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14141B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: permittedAccounts.map((acc) {
                        final isChecked = selectedUserIds.contains(acc.userId);
                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          activeColor: const Color(0xFF0288D1),
                          title: Row(
                            children: [
                              Text(acc.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              if (acc.accountName != null && acc.accountName!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text('(${acc.accountName})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                              if (acc.isSelf) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          onChanged: isCreating ? null : (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedUserIds.add(acc.userId);
                              } else if (selectedUserIds.length > 1) {
                                selectedUserIds.remove(acc.userId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: uploadMissingToTargets,
                    activeColor: const Color(0xFF8A2387),
                    title: const Text(
                      'Download & Upload missing songs to selected member lockers',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Downloads playlist tracks and uploads them to the selected family members so songs are in their cloud lockers.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onChanged: isCreating ? null : (val) {
                      setDialogState(() {
                        uploadMissingToTargets = val ?? true;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.verified, size: 16, color: Colors.tealAccent),
                    SizedBox(width: 6),
                    Text('Mode: Locker Only (Verified Uploads)', style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                  ],
                ),
                if (isCreating) ...[
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Creating & Reconciling replica playlist...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isCreating
                  ? null
                  : () async {
                      final destName = destNameController.text.trim();
                      if (destName.isEmpty) return;

                      setDialogState(() {
                        isCreating = true;
                        errorMsg = null;
                      });

                      try {
                        final created = await apiService.createReplicatedPlaylist({
                          'source_playlist_id': playlist.id,
                          'source_playlist_name': playlist.title,
                          'destination_playlist_name': destName,
                          'enabled': true,
                          'target_user_ids': selectedUserIds.toList(),
                          'upload_missing_to_targets': uploadMissingToTargets,
                        });
                        if (uploadMissingToTargets) {
                          _startSyncPolling();
                        }
                        await apiService.syncReplicatedPlaylist(created.id);
                        await _loadReplicatedPlaylists();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _openReplicationModal(created);
                        }
                      } catch (e) {
                        setDialogState(() {
                          isCreating = false;
                          errorMsg = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Create & Sync Replica'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0288D1),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReplicationModal(ReplicatedPlaylistModel replica) async {
    bool isActionRunning = false;
    String? actionStatus;
    ReplicationPreviewModel? preview;
    bool isLoadingPreview = true;
    String? loadError;
    bool showExcludedDetails = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void fetchPreviewData() async {
            try {
              final p = await apiService.fetchReplicatedPlaylist(replica.id);
              if (ctx.mounted) {
                setModalState(() {
                  preview = p;
                  isLoadingPreview = false;
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setModalState(() {
                  loadError = e.toString().replaceFirst('Exception: ', '');
                  isLoadingPreview = false;
                });
              }
            }
          }

          if (isLoadingPreview && preview == null && loadError == null) {
            fetchPreviewData();
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E28),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            title: Row(
              children: [
                const Icon(Icons.sync_alt, color: Colors.tealAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Playlist Replication', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('1:1 Locker-Only Replica Engine', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.greenAccent),
                      SizedBox(width: 6),
                      Text('Watching', style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: isLoadingPreview
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
                    )
                  : loadError != null
                      ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Error loading replica: $loadError', style: const TextStyle(color: Colors.amberAccent)),
                        )
                      : preview == null
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No preview data available', style: TextStyle(color: Colors.grey)),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Config Details (Section 23 of plan)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF14141E),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      children: [
                                        _buildReplicaDetailRow('Source Playlist', preview!.sourcePlaylistName, Icons.queue_music),
                                        const Divider(height: 20, color: Colors.white10),
                                        _buildReplicaDetailRow('Locker Replica', preview!.destinationPlaylistName, Icons.cloud_done),
                                        const Divider(height: 20, color: Colors.white10),
                                        _buildReplicaDetailRow('Mode', 'Locker Only (1:1 Ordered)', Icons.lock),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Metrics Grid (Section 23 of plan)
                                  Row(
                                    children: [
                                      _buildMetricCard('Source Tracks', '${preview!.sourceTracksCount}', Colors.blueAccent),
                                      const SizedBox(width: 8),
                                      _buildMetricCard('Locker Matches', '${preview!.desiredTracksCount}', Colors.tealAccent),
                                      const SizedBox(width: 8),
                                      _buildMetricCard('Excluded', '${preview!.excludedCount}', Colors.amberAccent),
                                      const SizedBox(width: 8),
                                      _buildMetricCard('Destination', '${preview!.desiredTracksCount}', Colors.purpleAccent),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Excluded Tracks section (Section 24 & 25 of plan)
                                  if (preview!.excludedCount > 0) ...[
                                    InkWell(
                                      onTap: () {
                                        setModalState(() => showExcludedDetails = !showExcludedDetails);
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.info_outline, size: 16, color: Colors.amberAccent),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${preview!.excludedCount} tracks not uploaded to locker (excluded from replica)',
                                                style: const TextStyle(fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Icon(showExcludedDetails ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.amberAccent),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (showExcludedDetails) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        constraints: const BoxConstraints(maxHeight: 180),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF14141E),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white10),
                                        ),
                                        child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: preview!.excludedTracks.length,
                                          itemBuilder: (ctx, i) {
                                            final item = preview!.excludedTracks[i];
                                            return ListTile(
                                              dense: true,
                                              visualDensity: VisualDensity.compact,
                                              leading: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.amberAccent),
                                              title: Text('${item.artist} - ${item.title}', style: const TextStyle(fontSize: 13)),
                                              subtitle: Text(item.humanReason, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                  ],

                                  if (isActionRunning) ...[
                                    Row(
                                      children: [
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                        const SizedBox(width: 12),
                                        Text(actionStatus ?? 'Processing...', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ],
                              ),
                            ),
            ),
            actions: [
              TextButton(
                onPressed: isActionRunning
                    ? null
                    : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E28),
                            title: const Text('Delete Replica Configuration?'),
                            content: const Text('This removes the watcher configuration. The destination playlist on YouTube Music will not be deleted.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await apiService.deleteReplicatedPlaylist(replica.id);
                          await _loadReplicatedPlaylists();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) setState(() {});
                        }
                      },
                child: const Text('Delete Config', style: TextStyle(color: Colors.redAccent)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: isActionRunning ? null : () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: isActionRunning
                        ? null
                        : () async {
                            setModalState(() {
                              isActionRunning = true;
                              actionStatus = 'Running dry-run diff calculation...';
                            });
                            try {
                              final res = await apiService.dryRunReplicatedPlaylist(replica.id);
                              setModalState(() {
                                isActionRunning = false;
                                preview = res;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Dry Run Complete: ${res.actions.length} changes planned.')),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isActionRunning = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Dry run failed: $e'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.preview, size: 16),
                    label: const Text('Dry Run'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: isActionRunning
                        ? null
                        : () async {
                            setModalState(() {
                              isActionRunning = true;
                              actionStatus = 'Reconciling destination replica...';
                            });
                            try {
                              final res = await apiService.syncReplicatedPlaylist(replica.id);
                              await _loadReplicatedPlaylists();
                              setModalState(() {
                                isActionRunning = false;
                                preview = res;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Locker replica reconciled successfully!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isActionRunning = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Reconcile failed: $e'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReplicaDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF14141E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(title, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedPlaylist != null) {
      return _buildPlaylistDetailsView();
    }
    return _buildPlaylistsGridView();
  }

  Widget _buildPlaylistsGridView() {
    final isMobile = ResponsiveLayout.isMobile(context);
    final filteredPlaylists = _playlists.where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            AppPageHeader(
              title: 'YTM PLAYLISTS',
              subtitle: 'Browse playlists, compare tracks with locker uploads, and replicate 1:1',
              kicker: 'CLOUD PLAYLIST COLLECTIONS',
              actions: [
                if (_replicatedPlaylists.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _showAllReplicasDialog,
                    icon: const Icon(Icons.sync_alt, size: 16, color: AppColors.info),
                    label: Text('Replicas (${_replicatedPlaylists.length})'),
                  ),
                OutlinedButton.icon(
                  onPressed: _showImportPlaylistDialog,
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Import URL'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loadPlaylists,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Search Bar
            AppSearchBar(
              hintText: 'Search playlists by name or description...',
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              onClear: () => setState(() => _searchQuery = ''),
            ),
            const SizedBox(height: AppSpacing.md),

            // Content
            Expanded(
              child: _buildPlaylistsContent(filteredPlaylists),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsContent(List<YTMPlaylist> playlists) {
    if (_isLoading) {
      return const Center(
        child: AppLoadingState(message: 'Loading YouTube Music playlists...'),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: AppErrorState(
          title: 'Failed to Load Playlists',
          message: _errorMessage!,
          onRetry: _loadPlaylists,
        ),
      );
    }

    if (playlists.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: Icons.playlist_play,
          title: 'No Playlists Found',
          description: _searchQuery.isEmpty
              ? 'No playlists found in your YouTube Music account.'
              : 'No playlists matched "$_searchQuery".',
          actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : null,
          onAction: _searchQuery.isNotEmpty ? () => setState(() => _searchQuery = '') : null,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 240).floor().clamp(2, 6);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.8,
          ),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final p = playlists[index];
            final isLikedMusic = p.id == 'LM';
            final hasActiveReplica = _replicatedPlaylists.any((r) => r.sourcePlaylistId == p.id);

            return InkWell(
              onTap: () => _selectPlaylist(p),
              borderRadius: AppRadius.card,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadius.card,
                  border: Border.all(
                    color: isLikedMusic
                        ? AppColors.primaryLight.withValues(alpha: 0.4)
                        : (hasActiveReplica
                            ? AppColors.info.withValues(alpha: 0.4)
                            : AppColors.borderSubtle),
                    width: (isLikedMusic || hasActiveReplica) ? 1.5 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Thumbnail
                    Expanded(
                      child: ClipRRect(
                        borderRadius: AppRadius.rSm,
                        child: Container(
                          width: double.infinity,
                          color: AppColors.surface,
                          child: isLikedMusic
                              ? Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF8A2387),
                                        Color(0xFFE94057),
                                        Color(0xFFF27121),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.thumb_up, color: Colors.white, size: 40),
                                  ),
                                )
                              : (p.thumbnail != null && p.thumbnail!.isNotEmpty
                                  ? Image.network(
                                      p.thumbnail!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(
                                          Icons.music_note,
                                          color: AppColors.textSecondary,
                                          size: 36,
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.playlist_play,
                                        color: AppColors.textSecondary,
                                        size: 40,
                                      ),
                                    )),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // Title
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Track count & badges
                    Row(
                      children: [
                        if (isLikedMusic)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryMuted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Auto Playlist',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          )
                        else if (p.trackCount != null)
                          Text(
                            '${p.trackCount} tracks',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          )
                        else
                          Text(
                            'Playlist',
                            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                          ),
                        const Spacer(),
                        if (hasActiveReplica)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.infoBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sync, size: 10, color: AppColors.info),
                                const SizedBox(width: 3),
                                Text(
                                  'Replica',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.info,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistDetailsView() {
    final isMobile = ResponsiveLayout.isMobile(context);
    final playlist = _selectedPlaylist!;
    final details = _playlistDetails;

    List<YTMPlaylistTrack> displayedTracks = [];
    int localCount = 0;
    int uploadsCount = 0;
    int streamingCount = 0;
    int missingFromUploadsCount = 0;

    if (details != null) {
      for (final t in details.tracks) {
        if (t.inLocal) localCount++;
        if (t.inUploads) uploadsCount++;
        if (!t.inUploads) missingFromUploadsCount++;
        if (!t.inLocal && !t.inUploads) streamingCount++;
      }

      displayedTracks = details.tracks.where((t) {
        if (_trackFilter == 'local' && !t.inLocal) return false;
        if (_trackFilter == 'uploads' && !t.inUploads) return false;
        if (_trackFilter == 'missing' && (t.inLocal || t.inUploads)) return false;
        return true;
      }).toList();
    }

    final isSyncRunning = _syncStatus != null && _syncStatus!.isRunning;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedPlaylist = null;
                      _playlistDetails = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to Playlists',
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppPageHeader(
                    title: playlist.title,
                    subtitle: playlist.description.isNotEmpty
                        ? playlist.description
                        : '${details?.tracks.length ?? 0} tracks in playlist',
                    kicker: 'PLAYLIST DETAILS',
                    actions: [
                      if (missingFromUploadsCount > 0)
                        ElevatedButton.icon(
                          onPressed: isSyncRunning ? null : _syncMissingTracks,
                          icon: const Icon(Icons.cloud_sync, size: 16),
                          label: Text(
                            isSyncRunning
                                ? 'Syncing...'
                                : 'Upload Missing ($missingFromUploadsCount)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      if (_currentReplicaConfig != null)
                        OutlinedButton.icon(
                          onPressed: () => _openReplicationModal(_currentReplicaConfig!),
                          icon: const Icon(Icons.sync_alt, size: 16, color: AppColors.info),
                          label: const Text('Manage Replica'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => _openCreateReplicaDialog(playlist),
                          icon: const Icon(Icons.copy_all, size: 16),
                          label: const Text('Make Replica'),
                        ),
                      IconButton(
                        onPressed: () => _selectPlaylist(playlist, refresh: true),
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Refresh Playlist',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Active Sync Banner
            if (isSyncRunning) ...[
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.info,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Downloading & Uploading: ${_syncStatus!.completedTracks}/${_syncStatus!.totalTracks} tracks',
                              style: AppTypography.label.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(_syncStatus!.progress * 100).toInt()}%',
                              style: AppTypography.label.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            InkWell(
                              onTap: () async {
                                try {
                                  await apiService.cancelPlaylistSync();
                                  _syncPollTimer?.cancel();
                                  if (mounted) {
                                    setState(() {
                                      _syncStatus = null;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Playlist sync cancelled.')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to cancel: $e'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.errorBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_syncStatus!.currentTrack != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Processing: ${_syncStatus!.currentTrack}',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _syncStatus!.progress,
                        backgroundColor: AppColors.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Compact Playlist Status Summary (Section 19 of plan.md)
            if (details != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PLAYLIST STATUS',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${details.tracks.isNotEmpty ? ((uploadsCount / details.tracks.length) * 100).toInt() : 100}% in Locker',
                          style: AppTypography.caption.copyWith(
                            color: missingFromUploadsCount == 0
                                ? AppColors.success
                                : AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: details.tracks.isNotEmpty
                            ? (uploadsCount / details.tracks.length).clamp(0.0, 1.0)
                            : 1.0,
                        minHeight: 6,
                        backgroundColor: AppColors.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          missingFromUploadsCount == 0 ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      children: [
                        Text(
                          '${details.tracks.length} total',
                          style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
                        ),
                        Text(
                          '$uploadsCount in locker',
                          style: AppTypography.caption.copyWith(color: AppColors.success),
                        ),
                        Text(
                          '$localCount local',
                          style: AppTypography.caption.copyWith(color: AppColors.info),
                        ),
                        Text(
                          '$missingFromUploadsCount missing',
                          style: AppTypography.caption.copyWith(
                            color: missingFromUploadsCount > 0
                                ? AppColors.warning
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filter Chips
              AppFilterBar<String>(
                options: [
                  FilterOption(
                    value: 'all',
                    label: 'All Tracks',
                    count: details.tracks.length,
                  ),
                  FilterOption(
                    value: 'local',
                    label: 'In Local Files',
                    count: localCount,
                  ),
                  FilterOption(
                    value: 'uploads',
                    label: 'In Cloud Locker',
                    count: uploadsCount,
                  ),
                  FilterOption(
                    value: 'missing',
                    label: 'Streaming Only',
                    count: streamingCount,
                  ),
                ],
                selectedValue: _trackFilter,
                onSelected: (val) => setState(() => _trackFilter = val),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Tracks Table / List
            Expanded(
              child: _buildPlaylistTracksContent(displayedTracks),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistTracksContent(List<YTMPlaylistTrack> tracks) {
    if (_isLoadingDetails) {
      return const Center(
        child: AppLoadingState(
          message: 'Fetching playlist tracks and comparing with locker uploads...',
        ),
      );
    }

    if (_detailsErrorMessage != null) {
      return Center(
        child: AppErrorState(
          title: 'Failed to Load Playlist Tracks',
          message: _detailsErrorMessage!,
          onRetry: () => _selectPlaylist(_selectedPlaylist!),
        ),
      );
    }

    if (tracks.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: Icons.music_off,
          title: 'No Tracks',
          description: _trackFilter == 'all'
              ? 'This playlist has no songs.'
              : 'No tracks match the selected filter "$_trackFilter".',
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ListView.separated(
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderSubtle),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final isDownloadingThis =
              track.videoId != null && _downloadingVideoIds.contains(track.videoId);

          return ListTile(
            leading: ClipRRect(
              borderRadius: AppRadius.rSm,
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.thumbnail != null && track.thumbnail!.isNotEmpty
                    ? Image.network(
                        track.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.music_note,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : const Icon(Icons.music_note, color: AppColors.textSecondary),
              ),
            ),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${track.displayArtist} • ${track.displayAlbum}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Local Library Badge
                if (track.inLocal)
                  Tooltip(
                    message: track.localPath ?? 'In Local Music Library',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_outlined, size: 12, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Local',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'No Local',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),

                // Uploads Badge / Action
                if (track.inUploads)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done_outlined, size: 12, color: AppColors.info),
                        SizedBox(width: 4),
                        Text(
                          'Locker',
                          style: TextStyle(
                            color: AppColors.info,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDownloadingThis)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _downloadAndUploadSingleTrack(track),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 13, color: AppColors.primary),
                    label: const Text(
                      'Download & Upload',
                      style: TextStyle(fontSize: 11, color: AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),

                const SizedBox(width: AppSpacing.md),
                Text(
                  track.formattedDuration,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
