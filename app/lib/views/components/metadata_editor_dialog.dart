import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class _ParsedFilenameParts {
  final String partA;
  final String partB;
  final String? trackNum;
  final bool isBySeparator;

  _ParsedFilenameParts({
    required this.partA,
    required this.partB,
    this.trackNum,
    required this.isBySeparator,
  });
}

class MetadataEditorDialog extends StatefulWidget {
  final MusicFile? song;
  final YtmUpload? ytmUpload;
  final String? trackVideoId;
  final String? initialTitle;
  final String? initialArtist;
  final String? initialAlbum;
  final String? initialThumbnail;

  const MetadataEditorDialog({
    super.key,
    this.song,
    this.ytmUpload,
    this.trackVideoId,
    this.initialTitle,
    this.initialArtist,
    this.initialAlbum,
    this.initialThumbnail,
  }) : assert(song != null || ytmUpload != null || trackVideoId != null);

  static Future<bool?> show(BuildContext context, MusicFile song) {
    return showDialog<bool>(
      context: context,
      builder: (context) => MetadataEditorDialog(song: song),
    );
  }

  static Future<dynamic> showForYtmUpload(BuildContext context, YtmUpload upload) {
    return showDialog<dynamic>(
      context: context,
      builder: (context) => MetadataEditorDialog(ytmUpload: upload),
    );
  }

  static Future<dynamic> showForTrack(
    BuildContext context, {
    required String videoId,
    required String title,
    String? artist,
    String? album,
    String? thumbnail,
  }) {
    return showDialog<dynamic>(
      context: context,
      builder: (context) => MetadataEditorDialog(
        trackVideoId: videoId,
        initialTitle: title,
        initialArtist: artist,
        initialAlbum: album,
        initialThumbnail: thumbnail,
      ),
    );
  }

  @override
  State<MetadataEditorDialog> createState() => _MetadataEditorDialogState();
}

class _MetadataEditorDialogState extends State<MetadataEditorDialog> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _trackNumController;
  late TextEditingController _searchQueryController;

  String? _selectedCoverUrl;
  Uint8List? _customCoverBytes;
  bool _isSearchingCover = false;

  bool _isSaving = false;
  String? _errorMessage;

  bool _isSearchingMb = false;
  List<MusicBrainzMatch>? _mbMatches;
  String? _mbSearchMessage;
  String _selectedProvider = 'all';

  static String _cleanRipperJunk(String name) {
    var s = name.replaceAll(
      RegExp(r'^(?:y2mate(?:\.com|\.is)?|snapsave(?:\.app|\.io)?|tuberipper(?:\.com)?|youtube)\s*[-_–]\s*', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\b(?:official\s+music\s+video|official\s+video|official\s+audio|lyrics\s+video|music\s+video|video\s+clip|official)\b', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s*[\(\[](?:official.*?|lyrics.*?|hd|hq|1080p|720p|audio|video)[\)\]]', caseSensitive: false),
      '',
    );
    if (s.contains('_') && !s.contains(' - ')) {
      s = s.replaceAll('_', ' ');
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void initState() {
    super.initState();
    final isTrack = widget.trackVideoId != null;
    final isYtm = widget.ytmUpload != null;
    final rawFilename = isTrack
        ? (widget.initialTitle ?? 'Track')
        : (isYtm ? widget.ytmUpload!.title : widget.song!.filename);
    String rawName = rawFilename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').trim();
    rawName = _cleanRipperJunk(rawName);

    String initialTitle = isTrack
        ? (widget.initialTitle ?? rawName)
        : ((isYtm ? widget.ytmUpload!.title : widget.song!.title) ?? rawName);
    if (initialTitle.toLowerCase().endsWith('.mp3') ||
        initialTitle.toLowerCase().endsWith('.flac') ||
        initialTitle.toLowerCase().endsWith('.m4a') ||
        initialTitle.toLowerCase().endsWith('.wav')) {
      initialTitle = rawName;
    }
    String initialArtist = isTrack
        ? (widget.initialArtist ?? '')
        : ((isYtm ? widget.ytmUpload!.artist : widget.song!.artist) ?? '');
    String initialAlbum = isTrack
        ? (widget.initialAlbum ?? '')
        : ((isYtm ? widget.ytmUpload!.album : widget.song!.album) ?? '');
    String initialTrackNum = (!isYtm && !isTrack && widget.song?.trackNumber != null)
        ? widget.song!.trackNumber.toString()
        : '';

    if (isTrack && widget.initialThumbnail != null && widget.initialThumbnail!.isNotEmpty) {
      _selectedCoverUrl = widget.initialThumbnail;
    } else if (isYtm && widget.ytmUpload!.thumbnail != null && widget.ytmUpload!.thumbnail!.isNotEmpty) {
      _selectedCoverUrl = widget.ytmUpload!.thumbnail;
    }

    // Auto-detect if artist is unknown or empty
    if (initialArtist.isEmpty || initialArtist.toLowerCase() == 'unknown artist') {
      final parts = _extractParts(rawName);
      if (parts != null) {
        if (parts.isBySeparator) {
          // "alone by tech nine" -> Title: "alone", Artist: "tech nine"
          initialTitle = parts.partA;
          initialArtist = parts.partB;
        } else {
          // "Akon - I Wanna Love You" -> Artist: "Akon", Title: "I Wanna Love You"
          initialArtist = parts.partA;
          initialTitle = parts.partB;
        }
        if (parts.trackNum != null) {
          initialTrackNum = parts.trackNum!;
        }
      }
    }

    _titleController = TextEditingController(text: initialTitle);
    _artistController = TextEditingController(text: initialArtist);
    _albumController = TextEditingController(text: initialAlbum);
    _trackNumController = TextEditingController(text: initialTrackNum);

    final initialSearch = (initialArtist.isNotEmpty && initialTitle.isNotEmpty)
        ? '$initialArtist - $initialTitle'
        : (initialTitle.isNotEmpty ? initialTitle : rawName);
    _searchQueryController = TextEditingController(text: initialSearch);

    // If initial artist has feat/ft, normalize immediately
    _normalizeFeaturedArtists();

    // Automatically search online metadata on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_mbMatches == null || _mbMatches!.isEmpty)) {
        _searchMusicBrainz();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _trackNumController.dispose();
    _searchQueryController.dispose();
    super.dispose();
  }

  _ParsedFilenameParts? _extractParts(String rawName) {
    String cleanName = _cleanRipperJunk(rawName.trim());
    String? trackNum;

    final trackPrefixMatch = RegExp(r'^(\d+)\s*[-._\s]\s*(.+)$').firstMatch(cleanName);
    if (trackPrefixMatch != null) {
      trackNum = trackPrefixMatch.group(1);
      cleanName = trackPrefixMatch.group(2)!.trim();
    }

    // 0. Pattern: "Artist ft. Features Title" without hyphens
    // e.g. "C-Mob ft. Brotha Lynch Hung, Twisted Insane, & C. Ray For Some Strange Reason"
    final featMatchNoHyphen = RegExp(
      r"^(.*?)\s+(?:ft\.|feat\.|featuring)\s+(.+?)\s+([A-Z0-9][a-zA-Z0-9\s,&’'-]+)$",
      caseSensitive: false,
    ).firstMatch(cleanName);
    if (featMatchNoHyphen != null && !cleanName.contains(' - ') && !cleanName.contains(' by ')) {
      final mainArtist = featMatchNoHyphen.group(1)!.trim();
      final features = featMatchNoHyphen.group(2)!.trim();
      final songTitle = featMatchNoHyphen.group(3)!.trim();
      return _ParsedFilenameParts(
        partA: mainArtist,
        partB: '$songTitle ft. $features',
        trackNum: trackNum,
        isBySeparator: false,
      );
    }

    // 1. "by" separator: e.g. "alone by tech nine"
    final matchBy = RegExp(r'^(.+?)\s+by\s+(.+)$', caseSensitive: false).firstMatch(cleanName);
    if (matchBy != null) {
      var songTitle = matchBy.group(1)!.trim();
      var artistName = matchBy.group(2)!.trim();

      final featInArtist = RegExp(r'^(.*?)\s+(?:ft\.|feat\.|featuring)\s+(.+)$', caseSensitive: false).firstMatch(artistName);
      if (featInArtist != null) {
        final mainArtist = featInArtist.group(1)!.trim();
        final features = featInArtist.group(2)!.trim();
        artistName = mainArtist;
        if (!RegExp(r'\b(?:ft\.|feat\.|featuring)\b', caseSensitive: false).hasMatch(songTitle)) {
          songTitle = '$songTitle ft. $features';
        }
      }

      return _ParsedFilenameParts(
        partA: songTitle,
        partB: artistName,
        trackNum: trackNum,
        isBySeparator: true,
      );
    }

    // 2. " - " separator
    if (cleanName.contains(' - ')) {
      final parts = cleanName.split(' - ');
      var pA = parts[0].trim();
      var pB = parts.sublist(1).join(' - ').trim();

      final featInA = RegExp(r'^(.*?)\s+(?:ft\.|feat\.|featuring)\s+(.+)$', caseSensitive: false).firstMatch(pA);
      if (featInA != null) {
        final mainArtist = featInA.group(1)!.trim();
        final features = featInA.group(2)!.trim();
        pA = mainArtist;
        if (!RegExp(r'\b(?:ft\.|feat\.|featuring)\b', caseSensitive: false).hasMatch(pB)) {
          pB = '$pB ft. $features';
        }
      }

      return _ParsedFilenameParts(
        partA: pA,
        partB: pB,
        trackNum: trackNum,
        isBySeparator: false,
      );
    }

    // 3. " _ " separator
    if (cleanName.contains(' _ ')) {
      final parts = cleanName.split(' _ ');
      return _ParsedFilenameParts(
        partA: parts[0].trim(),
        partB: parts.sublist(1).join(' _ ').trim(),
        trackNum: trackNum,
        isBySeparator: false,
      );
    }

    // 4. Underscores
    if (cleanName.contains('_')) {
      final parts = cleanName.split('_');
      return _ParsedFilenameParts(
        partA: parts[0].trim(),
        partB: parts.sublist(1).join(' ').trim(),
        trackNum: trackNum,
        isBySeparator: false,
      );
    }

    // 5. Hyphen
    if (cleanName.contains('-')) {
      final parts = cleanName.split('-');
      return _ParsedFilenameParts(
        partA: parts[0].trim(),
        partB: parts.sublist(1).join('-').trim(),
        trackNum: trackNum,
        isBySeparator: false,
      );
    }

    return null;
  }

  void _normalizeFeaturedArtists() {
    final artist = _artistController.text.trim();
    final featMatch = RegExp(r'^(.*?)\s+(?:ft\.|feat\.|featuring)\s+(.+)$', caseSensitive: false).firstMatch(artist);
    if (featMatch != null) {
      final mainArtist = featMatch.group(1)!.trim();
      final features = featMatch.group(2)!.trim();
      final title = _titleController.text.trim();

      setState(() {
        _artistController.text = mainArtist;
        if (!RegExp(r'\b(?:ft\.|feat\.|featuring)\b', caseSensitive: false).hasMatch(title)) {
          _titleController.text = '$title ft. $features';
        }
      });
    }
  }

  /// Automatically parses filename into Artist and Title based on requested order
  void _smartSplit({required bool artistFirst}) {
    final rawFilename = widget.ytmUpload != null ? widget.ytmUpload!.title : (widget.song?.filename ?? '');
    final rawName = rawFilename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').trim();
    final parts = _extractParts(rawName);

    if (parts != null) {
      setState(() {
        if (artistFirst) {
          // Artist gets partA, Title gets partB
          _artistController.text = parts.partA;
          _titleController.text = parts.partB;
        } else {
          // Title gets partA, Artist gets partB
          _titleController.text = parts.partA;
          _artistController.text = parts.partB;
        }
        if (parts.trackNum != null && parts.trackNum!.isNotEmpty) {
          _trackNumController.text = parts.trackNum!;
        }
      });
      _normalizeFeaturedArtists();
      _notifyAutoFill(artistFirst ? 'Artist - Title' : 'Title - Artist');
    } else {
      setState(() {
        _titleController.text = rawName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No separator found; used filename as Title.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _swapArtistTitle() {
    final curTitle = _titleController.text;
    final curArtist = _artistController.text;
    setState(() {
      _titleController.text = curArtist;
      _artistController.text = curTitle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Swapped Title ⇄ Artist'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _notifyAutoFill(String mode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Auto-filled as $mode!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _searchMusicBrainz({String? query}) async {
    setState(() {
      _isSearchingMb = true;
      _mbSearchMessage = null;
    });

    try {
      final artist = _artistController.text.trim();
      final title = _titleController.text.trim();
      final searchBox = _searchQueryController.text.trim();

      String? q = query ?? (searchBox.isNotEmpty ? searchBox : null);
      if (q == null) {
        if (artist.isNotEmpty && title.isNotEmpty) {
          q = '$artist - $title';
        } else if (title.isNotEmpty) {
          q = title;
        } else {
          q = (widget.ytmUpload != null ? widget.ytmUpload!.title : (widget.song?.filename ?? '')).replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        }
      }

      final results = await apiService.searchMusicBrainz(
        query: q,
        artist: artist.isNotEmpty ? artist : null,
        title: title.isNotEmpty ? title : null,
        provider: _selectedProvider,
        limit: 6,
      );

      setState(() {
        _mbMatches = results;
        _isSearchingMb = false;
        if (results.isEmpty) {
          _mbSearchMessage = 'No matching tracks found. Try adjusting the search box above or switching providers.';
        }
      });
    } catch (e) {
      setState(() {
        _isSearchingMb = false;
        _mbSearchMessage = 'Error searching metadata: $e';
      });
    }
  }

  String _getProviderLoadingText() {
    switch (_selectedProvider) {
      case 'ytm':
        return 'Searching YouTube Music...';
      case 'musicbrainz':
        return 'Searching MusicBrainz database...';
      case 'deezer':
        return 'Searching Deezer catalog...';
      case 'itunes':
        return 'Searching Apple Music & iTunes...';
      default:
        return 'Searching YouTube Music, Deezer, Apple Music & MusicBrainz...';
    }
  }

  Widget _buildProviderChips() {
    final providers = [
      {'id': 'all', 'label': 'All Sources', 'icon': Icons.hub_outlined, 'color': AppColors.info},
      {'id': 'ytm', 'label': 'YouTube Music', 'icon': Icons.play_circle_fill, 'color': AppColors.primary},
      {'id': 'musicbrainz', 'label': 'MusicBrainz', 'icon': Icons.album, 'color': const Color(0xFFBA68C8)},
      {'id': 'deezer', 'label': 'Deezer', 'icon': Icons.graphic_eq, 'color': const Color(0xFFFF007F)},
      {'id': 'itunes', 'label': 'Apple Music', 'icon': Icons.apple, 'color': const Color(0xFFFC3C44)},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: providers.map((p) {
          final id = p['id'] as String;
          final label = p['label'] as String;
          final icon = p['icon'] as IconData;
          final brandColor = p['color'] as Color;
          final isSelected = _selectedProvider == id;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () {
                if (_selectedProvider != id) {
                  setState(() => _selectedProvider = id);
                  _searchMusicBrainz();
                }
              },
              borderRadius: AppRadius.rXl,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? brandColor.withValues(alpha: 0.18) : AppColors.surface,
                  borderRadius: AppRadius.rXl,
                  border: Border.all(
                    color: isSelected ? brandColor : AppColors.borderSubtle,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 13,
                      color: isSelected ? brandColor : AppColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _applyMbMatch(MusicBrainzMatch match, {bool andUpload = false}) {
    setState(() {
      _titleController.text = match.title;
      _artistController.text = match.artist;
      _searchQueryController.text = '${match.artist} - ${match.title}';
      if (match.album != null && match.album!.isNotEmpty) {
        _albumController.text = match.album!;
      }
      if (match.trackNumber != null) {
        _trackNumController.text = match.trackNumber.toString();
      }
      if (match.coverUrl != null && match.coverUrl!.isNotEmpty) {
        _selectedCoverUrl = match.coverUrl;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied tags: "${match.title}" by ${match.artist}!'),
        duration: const Duration(seconds: 2),
      ),
    );

    if (andUpload) {
      _saveMetadata(enqueueUpload: true);
    }
  }

  Future<void> _fetchCoverArt() async {
    final artist = _artistController.text.trim();
    if (artist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an Artist Name first.')),
      );
      return;
    }
    setState(() => _isSearchingCover = true);
    try {
      final url = await apiService.fetchCoverArtUrl(
        artist: artist,
        title: _titleController.text.trim(),
        album: _albumController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _isSearchingCover = false;
          if (url != null) {
            _customCoverBytes = null;
            _selectedCoverUrl = url;
          }
        });
        if (url != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Album cover art found & attached!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No cover art found for this track.')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingCover = false);
    }
  }

  Future<void> _pickCustomImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final ext = file.extension?.toLowerCase() ?? 'jpeg';
          final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
          final b64 = base64Encode(bytes);
          setState(() {
            _customCoverBytes = bytes;
            _selectedCoverUrl = 'data:$mime;base64,$b64';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Custom artwork loaded (${(bytes.lengthInBytes / 1024).round()} KB)'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pasteCoverUrl() async {
    final controller = TextEditingController(
      text: (_selectedCoverUrl != null && _selectedCoverUrl!.startsWith('http')) ? _selectedCoverUrl : '',
    );
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: const Row(
          children: [
            Icon(Icons.link, color: AppColors.info, size: 20),
            SizedBox(width: 8),
            Text('Enter Image URL', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a direct link to any JPG or PNG image on the web:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://example.com/album-art.jpg',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      setState(() {
        _customCoverBytes = null;
        _selectedCoverUrl = url;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom artwork URL attached!'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _removeCoverArt() {
    setState(() {
      _customCoverBytes = null;
      _selectedCoverUrl = null;
    });
  }

  Future<void> _saveMetadata({bool enqueueUpload = false}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Title is required');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final artist = _artistController.text.trim();
      final album = _albumController.text.trim();
      final trackNum = int.tryParse(_trackNumController.text.trim());

      if (widget.ytmUpload != null) {
        // YTM Upload Replace Mode
        final res = await apiService.replaceYtmUpload(
          widget.ytmUpload!.entityId,
          title: title,
          artist: artist.isNotEmpty ? artist : null,
          album: album.isNotEmpty ? album : null,
          trackNumber: trackNum,
          coverUrl: _selectedCoverUrl,
        );
        if (res['success'] != true) {
          throw Exception(res['error'] ?? 'Failed to replace upload');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Replaced & uploaded clean version of "$title" to YouTube Music!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop({
            'saved': true,
            'title': title,
            'artist': artist.isNotEmpty ? artist : null,
            'album': album.isNotEmpty ? album : null,
            'coverUrl': _selectedCoverUrl,
          });
        }
        return;
      }

      if (widget.trackVideoId != null) {
        // Track Needs-Help Resolve Mode
        final res = await apiService.resolveNeedsHelpTrack(
          widget.trackVideoId!,
          title: title,
          artist: artist.isNotEmpty ? artist : null,
          album: album.isNotEmpty ? album : null,
          thumbnail: _selectedCoverUrl,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Resolved & uploaded "$title" with verified metadata to YouTube Music!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop({
            'saved': true,
            'resolved': true,
            'title': title,
            'artist': artist.isNotEmpty ? artist : null,
            'album': album.isNotEmpty ? album : null,
            'coverUrl': _selectedCoverUrl,
            'res': res,
          });
        }
        return;
      }

      if (widget.song?.id == null) return;

      await apiService.updateSongMetadata(
        widget.song!.id!,
        title: title,
        artist: artist.isNotEmpty ? artist : null,
        album: album.isNotEmpty ? album : null,
        trackNumber: trackNum,
        coverUrl: _selectedCoverUrl,
      );

      if (enqueueUpload) {
        await apiService.uploadSong(widget.song!.id!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enqueueUpload ? 'Saved & enqueued "$title" for upload!' : 'Metadata updated for "$title"'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildSectionBadge(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              title,
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Divider(color: AppColors.borderSubtle, height: 1)),
        ],
      ),
    );
  }

  Widget _buildFileInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.ytmUpload != null ? Icons.cloud_done_outlined : Icons.audio_file_outlined,
                size: 14,
                color: widget.ytmUpload != null ? AppColors.info : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.ytmUpload != null ? widget.ytmUpload!.title : (widget.song?.filename ?? ''),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.ytmUpload != null
                ? 'YouTube Music Upload • ID: ${widget.ytmUpload!.videoId ?? widget.ytmUpload!.entityId}'
                : (widget.song?.path ?? ''),
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionBadge('BASIC INFORMATION', Icons.info_outline),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _titleController,
          onSubmitted: (_) => _searchMusicBrainz(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Song Title *',
            hintText: 'e.g. Uptown Girl',
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            border: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
            enabledBorder: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
            focusedBorder: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.primary)),
            prefixIcon: const Icon(Icons.title, size: 18, color: AppColors.textMuted),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, size: 18, color: AppColors.info),
              tooltip: 'Search online with this title & artist',
              onPressed: () => _searchMusicBrainz(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _artistController,
          onSubmitted: (_) => _searchMusicBrainz(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Artist Name *',
            hintText: 'e.g. Billy Joel',
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            border: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
            enabledBorder: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
            focusedBorder: const OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.primary)),
            prefixIcon: const Icon(Icons.person_outline, size: 18, color: AppColors.textMuted),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, size: 18, color: AppColors.info),
              tooltip: 'Search online with this artist & title',
              onPressed: () => _searchMusicBrainz(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackInfoSection(bool hasFeatInArtist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionBadge('TRACK INFORMATION', Icons.library_music_outlined),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _albumController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Album (Optional)',
                  hintText: 'e.g. An Innocent Man',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
                  enabledBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
                  focusedBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.primary)),
                  prefixIcon: Icon(Icons.album_outlined, size: 18, color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _trackNumController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Track #',
                  hintText: '1',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
                  enabledBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.borderSubtle)),
                  focusedBorder: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: BorderSide(color: AppColors.primary)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onPressed: () => _smartSplit(artistFirst: true),
              icon: const Icon(Icons.auto_fix_high, size: 14),
              label: const Text('Artist - Title', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onPressed: () => _smartSplit(artistFirst: false),
              icon: const Icon(Icons.auto_fix_high, size: 14),
              label: const Text('Title - Artist', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderSubtle),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onPressed: _swapArtistTitle,
              icon: const Icon(Icons.swap_vert, size: 14),
              label: const Text('Swap (⇄)', style: TextStyle(fontSize: 11)),
            ),
            if (hasFeatInArtist)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.warning),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onPressed: _normalizeFeaturedArtists,
                icon: const Icon(Icons.drive_file_move_outline, size: 14),
                label: const Text('Move ft. to Title', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildArtworkSection() {
    final hasCover = _customCoverBytes != null || (_selectedCoverUrl != null && _selectedCoverUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionBadge('ARTWORK', Icons.image_outlined),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: hasCover ? AppColors.info.withValues(alpha: 0.3) : AppColors.borderSubtle,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 450;
              final artWidget = Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.rSm,
                    child: _customCoverBytes != null
                        ? Image.memory(
                            _customCoverBytes!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : (_selectedCoverUrl != null && _selectedCoverUrl!.isNotEmpty)
                            ? (_selectedCoverUrl!.startsWith('data:image/')
                                ? Image.memory(
                                    base64Decode(_selectedCoverUrl!.split(',')[1]),
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    _selectedCoverUrl!,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 56,
                                      height: 56,
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.broken_image, size: 22, color: AppColors.textMuted),
                                    ),
                                  ))
                            : Container(
                                width: 56,
                                height: 56,
                                color: AppColors.surfaceElevated,
                                child: const Icon(Icons.album, size: 28, color: AppColors.textMuted),
                              ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Cover Art', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: _customCoverBytes != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: const BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: AppRadius.badge,
                                      ),
                                      child: const Text('Custom Image', style: TextStyle(fontSize: 10, color: AppColors.info, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    )
                                  : (_selectedCoverUrl != null && _selectedCoverUrl!.isNotEmpty)
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(alpha: 0.2),
                                            borderRadius: AppRadius.badge,
                                          ),
                                          child: const Text('Attached', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: 0.2),
                                            borderRadius: AppRadius.badge,
                                          ),
                                          child: const Text('Auto-fetches on upload', style: TextStyle(fontSize: 10, color: AppColors.warning), overflow: TextOverflow.ellipsis),
                                        ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasCover
                              ? 'Embedded into audio tags before upload.'
                              : 'Searched & embedded automatically when uploaded.',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actionButtons = Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      minimumSize: const Size(40, 30),
                      side: const BorderSide(color: AppColors.info),
                      foregroundColor: AppColors.info,
                    ),
                    onPressed: _pickCustomImage,
                    icon: const Icon(Icons.file_upload_outlined, size: 14),
                    label: const Text('File', style: TextStyle(fontSize: 11)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      minimumSize: const Size(40, 30),
                      side: const BorderSide(color: AppColors.borderSubtle),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    onPressed: _pasteCoverUrl,
                    icon: const Icon(Icons.link, size: 14),
                    label: const Text('URL', style: TextStyle(fontSize: 11)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      minimumSize: const Size(40, 30),
                      side: const BorderSide(color: AppColors.borderSubtle),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    onPressed: _isSearchingCover ? null : _fetchCoverArt,
                    icon: _isSearchingCover
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info))
                        : const Icon(Icons.image_search, size: 14),
                    label: const Text('Fetch', style: TextStyle(fontSize: 11)),
                  ),
                  if (hasCover)
                    IconButton(
                      tooltip: 'Remove artwork',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                      hoverColor: AppColors.error.withValues(alpha: 0.1),
                      onPressed: _removeCoverArt,
                    ),
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    artWidget,
                    const SizedBox(height: AppSpacing.sm),
                    actionButtons,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: artWidget),
                  const SizedBox(width: AppSpacing.xs),
                  actionButtons,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMatchCard(MusicBrainzMatch match) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.rXs,
            child: (match.coverUrl != null && match.coverUrl!.isNotEmpty)
                ? Image.network(
                    match.coverUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.surface,
                      child: const Icon(Icons.album, size: 22, color: AppColors.textMuted),
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: AppColors.surface,
                    child: const Icon(Icons.album, size: 22, color: AppColors.textMuted),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: match.source == 'YouTube Music'
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : match.source == 'Deezer'
                                ? AppColors.streaming.withValues(alpha: 0.2)
                                : AppColors.info.withValues(alpha: 0.2),
                        borderRadius: AppRadius.badge,
                      ),
                      child: Text(
                        match.source,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: match.source == 'YouTube Music'
                              ? AppColors.primary
                              : match.source == 'Deezer'
                                  ? AppColors.streaming
                                  : AppColors.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: match.score >= 90
                            ? AppColors.success.withValues(alpha: 0.2)
                            : AppColors.warning.withValues(alpha: 0.2),
                        borderRadius: AppRadius.badge,
                      ),
                      child: Text(
                        '${match.score}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: match.score >= 90 ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Artist: ${match.artist}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (match.album != null && match.album!.isNotEmpty)
                  Text(
                    'Album: ${match.album}${match.releaseDate != null ? ' (${match.releaseDate!.split('-')[0]})' : ''}${match.trackNumber != null ? ' • Track #${match.trackNumber}' : ''}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(54, 26),
                  side: const BorderSide(color: AppColors.info),
                  foregroundColor: AppColors.info,
                ),
                onPressed: () => _applyMbMatch(match),
                child: const Text('Apply', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(54, 26),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _applyMbMatch(match, andUpload: true),
                child: const Text('Upload', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildYtmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionBadge('YOUTUBE MUSIC', Icons.cloud_queue_outlined),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.input,
            border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchQueryController,
                  onSubmitted: (val) => _searchMusicBrainz(query: val),
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Search online metadata (e.g. Billy Joel - Uptown Girl)',
                    hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.info),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.sm)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _isSearchingMb ? null : () => _searchMusicBrainz(query: _searchQueryController.text.trim()),
                child: _isSearchingMb
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildProviderChips(),
        if (_isSearchingMb) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info)),
                const SizedBox(width: 10),
                Text(_getProviderLoadingText(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
        if (_mbSearchMessage != null && !_isSearchingMb) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(_mbSearchMessage!, style: const TextStyle(fontSize: 11, color: AppColors.warning))),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                  onPressed: () => setState(() => _mbSearchMessage = null),
                ),
              ],
            ),
          ),
        ],
        if (_mbMatches != null && _mbMatches!.isNotEmpty && !_isSearchingMb) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
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
                        const Icon(Icons.travel_explore, size: 14, color: AppColors.info),
                        const SizedBox(width: 6),
                        Text(
                          'Online Matches (${_mbMatches!.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.info),
                        ),
                      ],
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                      onPressed: () => setState(() => _mbMatches = null),
                      tooltip: 'Close matches',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._mbMatches!.map((match) => _buildMatchCard(match)),
              ],
            ),
          ),
        ],
        if (_isSaving && widget.ytmUpload != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Downloading audio from YouTube Music, applying tags, and replacing upload... This may take up to a minute.',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 460;
        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.trackVideoId != null) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _isSaving ? null : () => _saveMetadata(),
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_download, size: 16),
                    label: Text(_isSaving ? 'Resolving & Uploading...' : 'Download & Upload with Match'),
                  ),
                ] else if (widget.ytmUpload != null) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _isSaving ? null : () => _saveMetadata(),
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.published_with_changes, size: 16),
                    label: Text(_isSaving ? 'Replacing on YTM...' : 'Retag & Replace on YTM'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isSaving ? null : () => _saveMetadata(enqueueUpload: true),
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload, size: 16),
                    label: const Text('Save & Upload'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton.tonal(
                    onPressed: _isSaving ? null : () => _saveMetadata(enqueueUpload: false),
                    child: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save Metadata'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.borderSubtle),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.borderSubtle),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (widget.trackVideoId != null) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: _isSaving ? null : () => _saveMetadata(),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_download, size: 16),
                  label: Text(_isSaving ? 'Resolving & Uploading...' : 'Download & Upload with Match'),
                ),
              ] else if (widget.ytmUpload != null) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: _isSaving ? null : () => _saveMetadata(),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.published_with_changes, size: 16),
                  label: Text(_isSaving ? 'Replacing on YTM...' : 'Retag & Replace on YTM'),
                ),
              ] else ...[
                FilledButton.tonal(
                  onPressed: _isSaving ? null : () => _saveMetadata(enqueueUpload: false),
                  child: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Metadata'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSaving ? null : () => _saveMetadata(enqueueUpload: true),
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload, size: 16),
                  label: const Text('Save & Upload'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFeatInArtist = _artistController.text.contains(RegExp(r'\b(?:ft\.|feat\.|featuring)\b', caseSensitive: false));
    final isMobile = ResponsiveLayout.isMobile(context) || MediaQuery.of(context).size.width < 600;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      insetPadding: isMobile
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: isMobile ? AppRadius.card : AppRadius.dialog,
      ),
      child: Container(
        width: isMobile ? screenWidth : 620,
        constraints: BoxConstraints(
          maxHeight: isMobile ? screenHeight * 0.96 : screenHeight * 0.9,
          maxWidth: isMobile ? screenWidth : 620,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pinned Header
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          widget.ytmUpload != null ? Icons.cloud_sync_outlined : Icons.edit_note,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            widget.ytmUpload != null ? 'Retag & Replace YTM Upload' : 'Edit Track Metadata',
                            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderSubtle, height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFileInfoCard(),
                    _buildBasicInfoSection(),
                    _buildTrackInfoSection(hasFeatInArtist),
                    _buildArtworkSection(),
                    _buildYtmSection(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(color: AppColors.borderSubtle, height: 1),

            // Pinned Bottom Actions
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }
}
