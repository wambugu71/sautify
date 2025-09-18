/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
// New imports for download/offline
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/apis/music_api.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/providers/fetch_home_Section.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/screens/playlist_overlay_screen.dart';
import 'package:sautifyv2/screens/search_overlay_screen.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:skeletonizer/skeletonizer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ValueNotifier<Set<String>> _downloading = ValueNotifier<Set<String>>(
    {},
  );
  Box<String>? _downloadsBox;
  // Simple tap throttle timestamp to prevent rapid double taps,surprisingly it works
  DateTime _lastActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initDownloadsBox();
  }

  Future<void> _initDownloadsBox() async {
    try {
      await Hive.initFlutter();
    } catch (_) {}
    _downloadsBox = Hive.isBoxOpen('downloads_box')
        ? Hive.box<String>('downloads_box')
        : await Hive.openBox<String>('downloads_box');
    if (mounted) setState(() {});
  }

  void _setDownloading(String key, bool value) {
    final s = Set<String>.from(_downloading.value);
    if (value) {
      s.add(key);
    } else {
      s.remove(key);
    }
    _downloading.value = s;
  }

  bool _throttle([int debounceMs = 600]) {
    final now = DateTime.now();
    if (now.difference(_lastActionAt).inMilliseconds < debounceMs) {
      return false;
    }
    _lastActionAt = now;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => HomeNotifier(),
      child: Scaffold(
        backgroundColor: bgcolor,
        appBar: AppBar(
          elevation: 0,
          title: const Text(
            'S A U T I F Y',
            style: TextStyle(
              fontFamily: 'asimovian',
              fontWeight: FontWeight.bold,
              fontSize: 24,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
          backgroundColor: appbarcolor,
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: appbarcolor.withAlpha(155),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: IconButton(
                    icon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white,
                      opticalSize: 24,
                      weight: 800,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const SearchOverlayScreen(),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: appbarcolor.withAlpha(155),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  // Use a Builder to obtain a context that is below the
                  // ChangeNotifierProvider so Provider.of/read works.
                  child: Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        ctx.read<HomeNotifier>().fetchHomeSections();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Consumer<HomeNotifier>(
          builder: (context, homeNotifier, child) {
            if (homeNotifier.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Error: ${homeNotifier.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => homeNotifier.fetchHomeSections(),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              backgroundColor: bgcolor,
              elevation: 11,
              color: appbarcolor,
              onRefresh: () => homeNotifier.fetchHomeSections(),
              child: Skeletonizer(
                enabled:
                    homeNotifier.isLoading ||
                    !homeNotifier.isInitialized ||
                    homeNotifier.sections.isEmpty,
                effect: ShimmerEffect(
                  baseColor: cardcolor,
                  highlightColor: cardcolor.withAlpha(153), // 60% opacity
                  duration: const Duration(milliseconds: 1000),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: 100,
                  ), // Space for global mini player
                  itemCount: homeNotifier.sections.isEmpty
                      ? 5
                      : homeNotifier.sections
                            .where((section) => section.contents.isNotEmpty)
                            .length,
                  itemBuilder: (context, index) {
                    if (homeNotifier.sections.isEmpty) {
                      return _buildSkeletonSection();
                    }

                    final sectionsWithContent = homeNotifier.sections
                        .where((section) => section.contents.isNotEmpty)
                        .toList();

                    if (index >= sectionsWithContent.length) {
                      return const SizedBox.shrink();
                    }

                    final section = sectionsWithContent[index];
                    return _buildSectionWidget(context, section);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionWidget(BuildContext context, Section section) {
    if (section.contents.isEmpty) {
      return const SizedBox.shrink();
    }

    final isPlaylistSection = section.contents.any(
      (c) =>
          (c.playlistId?.isNotEmpty ?? false) ||
          c.type.toLowerCase().contains('playlist'),
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: txtcolor,
            ),
          ),
          const SizedBox(height: 12),
          // Use CarouselView for playlists, ListView for other sections
          if (isPlaylistSection)
            Builder(
              builder: (context) {
                // Only show items that have a valid playlistId to ensure navigation works
                final playlistItems = section.contents
                    .where((c) => (c.playlistId?.isNotEmpty ?? false))
                    .toList();

                if (playlistItems.isEmpty) {
                  // Fallback to horizontal list if no valid playlist IDs
                  return SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: section.contents.length,
                      itemBuilder: (context, index) {
                        final content = section.contents[index];
                        return _buildContentCard(context, content);
                      },
                    ),
                  );
                }

                // Use PageView to emulate a carousel with reliable tap gestures
                return SizedBox(
                  height: 230,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double itemWidth = 200.0;
                      const double gap = 20.0; // target ~20px spacing

                      final double maxW = constraints.maxWidth;
                      final double pageW = (itemWidth + gap).clamp(0.0, maxW);
                      double viewportFraction = pageW / maxW;
                      // Ensure fraction within sensible bounds
                      if (viewportFraction <= 0) viewportFraction = 0.9;
                      if (viewportFraction > 1) viewportFraction = 1.0;

                      final controller = PageController(
                        viewportFraction: viewportFraction,
                        keepPage: true,
                      );

                      return PageView.builder(
                        controller: controller,
                        padEnds: false,
                        pageSnapping: true,
                        physics: const PageScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: playlistItems.length,
                        itemBuilder: (context, i) {
                          final content = playlistItems[i];
                          return Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: itemWidth,
                              child: _buildContentCard(
                                context,
                                content,
                                showDownloadControls: false,
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => PlaylistOverlayScreen(
                                      playlistContent: content,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            )
          else
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: section.contents.length,
                itemBuilder: (context, index) {
                  final content = section.contents[index];
                  return _buildContentCard(context, content);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContentCard(
    BuildContext context,
    Contents content, {
    bool showDownloadControls = true,
    VoidCallback? onTap,
  }) {
    final key = content.videoId ?? content.playlistId ?? content.name;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _downloading,
      builder: (context, downloadingSet, _) {
        final isBusy = downloadingSet.contains(key);
        // offline badge for single tracks only
        final isDownloaded =
            content.videoId != null &&
            content.videoId!.isNotEmpty &&
            (_downloadsBox?.containsKey(content.videoId) ?? false);
        return Container(
          width: 200,
          margin: const EdgeInsets.only(right: 12),
          child: Material(
            color: cardcolor,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: isBusy
                  ? null
                  : () {
                      if (!_throttle()) return;
                      if (onTap != null) {
                        onTap();
                      } else {
                        _handleContentTap(context, content);
                      }
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Artwork + download button + offline badge
                  SizedBox(
                    height: 130,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            child: content.thumbnailUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: content.thumbnailUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: Icon(
                                        Icons.music_note,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (showDownloadControls && isDownloaded)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.offline_pin,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Offline',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (showDownloadControls)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: InkWell(
                              onTap: isBusy
                                  ? null
                                  : () {
                                      if (!_throttle()) return;
                                      _onDownloadPressed(context, content);
                                    },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: isBusy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Texts
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          content.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: txtcolor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          content.artistName,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            content.type,
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: cardcolor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (context, index) {
                return _buildSkeletonCard();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        color: cardcolor,
        elevation: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    color: cardcolor.withAlpha(179), // 70% opacity
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(179), // 70% opacity
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(128), // 50% opacity
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 16,
                      width: 50,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(179), // 70% opacity
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleContentTap(BuildContext context, Contents content) {
    // If a downloaded/local version exists, prefer it
    final videoId = content.videoId;
    if (videoId != null && videoId.isNotEmpty) {
      final jsonStr = _downloadsBox?.get(videoId);
      if (jsonStr != null) {
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final filePath = data['filePath'] as String?;
          if (filePath != null && File(filePath).existsSync()) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PlayerScreen(
                  title: data['title'] as String? ?? content.name,
                  artist: data['artist'] as String? ?? content.artistName,
                  imageUrl: data['artPath'] as String? ?? content.thumbnailUrl,
                  // For local, pass single-item playlist via service entry point
                  playlist: [
                    StreamingData(
                      videoId: videoId,
                      title: data['title'] as String? ?? content.name,
                      artist: data['artist'] as String? ?? content.artistName,
                      thumbnailUrl:
                          data['imageUrl'] as String? ?? content.thumbnailUrl,
                      duration: null,
                      streamUrl: filePath,
                      isAvailable: true,
                      isLocal: true,
                    ),
                  ],
                  initialIndex: 0,
                  sourceType: 'OFFLINE',
                  sourceName: 'Downloads',
                ),
              ),
            );
            return;
          }
        } catch (_) {}
      }
    }

    // If we have a song videoId, go straight to player
    if ((content.type.toLowerCase().contains('song') ||
            content.type.toLowerCase().contains('track')) &&
        content.videoId != null &&
        content.videoId!.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            title: content.name,
            artist: content.artistName,
            imageUrl: content.thumbnailUrl,
            videoId: content.videoId,
            sourceType: 'HOME',
            sourceName: 'Home',
          ),
        ),
      );
      return;
    }

    // Check if it's a playlist type content
    if (content.type.toLowerCase().contains('playlist') ||
        content.playlistId != null) {
      if (content.playlistId != null && content.playlistId!.isNotEmpty) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => PlaylistOverlayScreen(playlistContent: content),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No playlist ID available'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      // Handle other content types (albums, etc.)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            title: content.name,
            artist: content.artistName,
            imageUrl: content.thumbnailUrl,
          ),
        ),
      );
    }
  }

  Future<void> _onDownloadPressed(
    BuildContext context,
    Contents content,
  ) async {
    final videoId = content.videoId;
    if (videoId == null || videoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No track to download for this item')),
      );
      return;
    }

    final key = videoId;
    _setDownloading(key, true);

    try {
      // Ask storage permission on Android
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Storage permission denied');
        }
      }

      // Resolve destination folder
      final Directory baseDir = Platform.isAndroid
          ? (await getExternalStorageDirectory()) ??
                await getApplicationDocumentsDirectory()
          : await getApplicationDocumentsDirectory();
      final Directory musicDir = Directory('${baseDir.path}/Sautify/Downloads');
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      // File name base
      final safeTitle = _sanitizeFileName(content.name);

      // Fetch stream URL via API service
      final api = Api();
      final url = await api.getDownloadUrl(videoId);
      final meta = api.getMetadata; // artist, title, thumbnail, duration

      // Decide file extension from URL/mime (Explode often returns webm/opus)
      final ext = _inferAudioExtensionFromUrl(url);
      final filePath = '${musicDir.path}/$safeTitle$ext';
      final file = File(filePath);

      // Download bytes with HTTP
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        throw Exception('Failed to download audio');
      }
      await file.writeAsBytes(resp.bodyBytes);

      // Save artwork alongside and basic metadata json
      String? artPath;
      if (meta.thumbnail.isNotEmpty) {
        try {
          final artResp = await http.get(Uri.parse(meta.thumbnail));
          if (artResp.statusCode == 200) {
            final artFile = File('${musicDir.path}/$safeTitle.jpg');
            await artFile.writeAsBytes(artResp.bodyBytes);
            artPath = artFile.path;
          }
        } catch (_) {}
      }

      // Save a small sidecar JSON with metadata for offline browsing
      final metaJson = {
        'videoId': videoId,
        'title': meta.title.isNotEmpty ? meta.title : content.name,
        'artist': content.artistName,
        'artPath': artPath,
        'imageUrl': meta.thumbnail,
        'filePath': file.path,
        'downloadedAt': DateTime.now().toIso8601String(),
      };

      await _downloadsBox?.put(videoId, jsonEncode(metaJson));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloaded \'${content.name}\'')));
      // Trigger rebuild to show offline badge
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      _setDownloading(key, false);
    }
  }

  // Infer proper audio extension from URL or mime hints
  String _inferAudioExtensionFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('mime=audio%2fwebm') ||
        u.contains('audio/webm') ||
        u.endsWith('.webm')) {
      return '.webm';
    }
    if (u.contains('mime=audio%2fmp4') ||
        u.contains('audio/mp4') ||
        u.endsWith('.m4a')) {
      return '.m4a';
    }
    if (u.endsWith('.mp3')) {
      return '.mp3';
    }
    // Default to mp3 for legacy
    return '.mp3';
  }

  String _sanitizeFileName(String s) {
    // just for  the crazy youtube namings by some artists lol.
    final illegal = RegExp(r'[\\/:*?"<>|]');
    return s.replaceAll(illegal, '_');
  }
}
