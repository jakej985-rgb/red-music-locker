import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class FolderBrowserDialog extends StatefulWidget {
  final String? initialPath;

  const FolderBrowserDialog({super.key, this.initialPath});

  static Future<String?> show(BuildContext context, {String? initialPath}) {
    return showDialog<String>(
      context: context,
      builder: (context) => FolderBrowserDialog(initialPath: initialPath),
    );
  }

  @override
  State<FolderBrowserDialog> createState() => _FolderBrowserDialogState();
}

class _FolderBrowserDialogState extends State<FolderBrowserDialog> {
  final TextEditingController _pathController = TextEditingController();
  FsBrowseResult? _browseResult;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDirectory(widget.initialPath ?? '/music');
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await apiService.browseFilesystem(path);
      if (mounted) {
        setState(() {
          _browseResult = res;
          _pathController.text = res.currentPath;
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

  void _navigateToParent() {
    if (_browseResult?.parentPath != null) {
      _loadDirectory(_browseResult!.parentPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: Container(
        width: 620,
        height: 520,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_open, color: AppColors.info, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Select Root Folder',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Browsing internal Docker container filesystem. Select the folder where your audio files are mounted.',
              style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),

            // Quick shortcuts
            Row(
              children: [
                const Text('Quick Access: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                _buildQuickChip('/music'),
                const SizedBox(width: 6),
                _buildQuickChip('/downloads'),
              ],
            ),
            const SizedBox(height: 12),

            // Path navigation input & Up button
            Row(
              children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceSubtle,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  onPressed: (_browseResult?.parentPath != null && !_isLoading)
                      ? _navigateToParent
                      : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Up one directory',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.button,
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textMuted),
                    ),
                    onSubmitted: (val) => _loadDirectory(val.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceSubtle,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                  onPressed: _isLoading ? null : () => _loadDirectory(_pathController.text.trim()),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Reload directory',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Directory listing content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: _buildDirectoryList(),
              ),
            ),
            const SizedBox(height: 14),

            // Bottom bar: Free Space & Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_browseResult != null)
                  Row(
                    children: [
                      const Icon(Icons.storage, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Free: ${_browseResult!.freeSpace} / Total: ${_browseResult!.totalSpace}',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontFamily: 'monospace'),
                      ),
                    ],
                  )
                else
                  const SizedBox(),
                Row(
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                        side: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                      onPressed: () {
                        final selected = _pathController.text.trim();
                        if (selected.isNotEmpty) {
                          Navigator.of(context).pop(selected);
                        }
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.check, size: 16),
                          SizedBox(width: 6),
                          Text('Select Folder', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String path) {
    return InkWell(
      onTap: () => _loadDirectory(path),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Text(
          path,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.info),
        ),
      ),
    );
  }

  Widget _buildDirectoryList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.info),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36, color: AppColors.warning),
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.warning, fontSize: 12)),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceElevated,
                  foregroundColor: AppColors.textPrimary,
                ),
                onPressed: () => _loadDirectory('/'),
                child: const Text('Go to Root (/)'),
              ),
            ],
          ),
        ),
      );
    }

    final dirs = _browseResult?.directories ?? [];
    if (dirs.isEmpty) {
      return Center(
        child: Text(
          'No subdirectories found in this folder.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      itemCount: dirs.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderSubtle),
      itemBuilder: (context, index) {
        final d = dirs[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.folder, color: AppColors.info, size: 20),
          title: Text(
            d.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          onTap: () => _loadDirectory(d.path),
        );
      },
    );
  }
}
