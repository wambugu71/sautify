/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// --- New imports for downloads/offline ---
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/apis/music_api.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/providers/library_provider.dart';
import 'package:sautifyv2/providers/playlist_provider.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistOverlayScreen extends StatefulWidget {
  final Contents playlistContent;

  const PlaylistOverlayScreen({super.key, required this.playlistContent});

  @override
  State<PlaylistOverlayScreen> createState() => _PlaylistOverlayScreenState();
}

class _PlaylistOverlayScreenState extends State<PlaylistOverlayScreen> {
  final AudioPlayerService _audio = AudioPlayerService();
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);
  // Track ID of the item currently starting playback (for targeted spinner)
  final ValueNotifier<String?> _startingTrackId = ValueNotifier<String?>(null);
  // Track per-item download busy state
  final ValueNotifier<Set<String>> _downloading = ValueNotifier<Set<String>>(
    {},
  );
  Box<String>? _downloadsBox;
  // Bulk download state
  final ValueNotifier<bool> _bulkBusy = ValueNotifier<bool>(false);
  final ValueNotifier<int> _bulkDone = ValueNotifier<int>(0);
  final ValueNotifier<int> _bulkTotal = ValueNotifier<int>(0);
  late final PlaylistProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = PlaylistProvider(widget.playlistContent.playlistId ?? '');
    _initDownloadsBox();
    // Proactively resolve links for the first few tracks when the overlay opens.
    // This makes the first taps feel instant.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = _provider;
      // If data is already loaded, warm up; otherwise wait for first load event.
      if (provider.videos.isNotEmpty) {
        _warmFirstFew(provider);
      } else {
        // Listen once for the first successful load
        void listener() {
          if (provider.videos.isNotEmpty) {
            _warmFirstFew(provider);
            provider.removeListener(listener);
          }
        }

        provider.addListener(listener);
      }
    });
  }

  Future<void> _warmFirstFew(PlaylistProvider provider) async {
    try {
      final items = provider.videos.take(3).toList();
      if (items.isEmpty) return;
      final ids = items.map((v) => v.id.value).toList();
      // Use the audio service’s streaming service indirectly by building StreamingData
      // and letting AudioPlayerService warm in the background when loaded.
      // Here we trigger a direct warm-up via MusicStreamingService.
      // ignore: use_build_context_synchronously
      final service = MusicStreamingService();
      await service.batchGetStreamingUrls(ids);
      service.dispose();
    } catch (_) {}
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

  bool _isDownloaded(String videoId) {
    final box = _downloadsBox;
    if (box == null) return false;
    return box.containsKey(videoId);
  }

  @override
  void dispose() {
    _busy.dispose();
    _startingTrackId.dispose();
    _downloading.dispose();
    _bulkBusy.dispose();
    _bulkDone.dispose();
    _bulkTotal.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: bgcolor.withOpacity(0.95),
        body: SafeArea(
          child: Consumer<PlaylistProvider>(
            builder: (context, playlistProvider, child) {
              return Stack(
                children: [
                  // Background gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bgcolor.withOpacity(0.8), bgcolor],
                      ),
                    ),
                  ),
                  // Foreground content
                  Column(
                    children: [
                      _buildHeader(context),
                      _buildPlaylistInfo(context, playlistProvider),
                      Expanded(child: _buildVideosList(playlistProvider)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.keyboard_arrow_down, color: iconcolor, size: 32),
          ),
          Expanded(
            child: Text(
              'Playlist',
              style: TextStyle(
                color: txtcolor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 48), // Balance the close button
        ],
      ),
    );
  }

  Widget _buildPlaylistInfo(BuildContext context, PlaylistProvider provider) {
    final hasTracks = provider.videos.isNotEmpty;
    final playlistId = widget.playlistContent.playlistId ?? '';
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Playlist thumbnail
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cardcolor,
            ),
            child: widget.playlistContent.thumbnailUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: widget.playlistContent.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: Icon(
                        Icons.playlist_play,
                        size: 60,
                        color: iconcolor.withOpacity(0.6),
                      ),
                    ),
                  )
                : Icon(
                    Icons.playlist_play,
                    size: 60,
                    color: iconcolor.withOpacity(0.6),
                  ),
          ),

          const SizedBox(width: 16),

          // Playlist details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlistContent.name,
                  style: TextStyle(
                    color: txtcolor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.playlistContent.artistName,
                  style: TextStyle(
                    color: txtcolor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: appbarcolor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.playlistContent.type.toUpperCase(),
                    style: TextStyle(
                      color: appbarcolor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Play + Save + Download All
                SizedBox(
                  height: 40,
                  child: ListView(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _busy,
                        builder: (context, busy, __) {
                          final disabled =
                              !hasTracks || busy || _audio.isPreparing.value;
                          return ElevatedButton.icon(
                            onPressed: disabled
                                ? null
                                : () async {
                                    if (busy || _audio.isPreparing.value)
                                      return;
                                    _busy.value = true;
                                    try {
                                      final playlist = provider.videos
                                          .map(
                                            (v) => StreamingData(
                                              videoId: v.id.value,
                                              title: v.title,
                                              artist: v.author,
                                              thumbnailUrl:
                                                  v.thumbnails.highResUrl,
                                              duration: v.duration,
                                            ),
                                          )
                                          .toList();
                                      await _audio.stop();
                                      await _audio.loadPlaylist(
                                        playlist,
                                        initialIndex: 0,
                                        autoPlay: true,
                                        sourceType: 'PLAYLIST',
                                        sourceName: widget.playlistContent.name,
                                      );
                                      if (mounted) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => PlayerScreen(
                                              title: playlist.first.title,
                                              artist: playlist.first.artist,
                                              imageUrl:
                                                  playlist.first.thumbnailUrl,
                                              duration: playlist.first.duration,
                                            ),
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) _busy.value = false;
                                    }
                                  },
                            icon: disabled
                                ? const SizedBox.shrink()
                                : const Icon(Icons.play_arrow),
                            label: disabled
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Play'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appbarcolor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 2),
                      Consumer<LibraryProvider>(
                        builder: (context, lib, _) {
                          final isSaved =
                              playlistId.isNotEmpty &&
                              lib.getPlaylists().any((p) => p.id == playlistId);
                          return OutlinedButton.icon(
                            onPressed: (!hasTracks || playlistId.isEmpty)
                                ? null
                                : () async {
                                    if (isSaved) {
                                      await lib.deletePlaylist(playlistId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Removed from Library',
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      final tracks = provider.videos
                                          .map(
                                            (v) => StreamingData(
                                              videoId: v.id.value,
                                              title: v.title,
                                              artist: v.author,
                                              thumbnailUrl:
                                                  v.thumbnails.highResUrl,
                                              duration: v.duration,
                                            ),
                                          )
                                          .toList();
                                      final saved = SavedPlaylist(
                                        id: playlistId,
                                        title: widget.playlistContent.name,
                                        artworkUrl:
                                            widget.playlistContent.thumbnailUrl,
                                        tracks: tracks,
                                      );
                                      await lib.savePlaylist(saved);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Saved to Library'),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: Icon(
                              isSaved ? Icons.favorite : Icons.favorite_border,
                              color: isSaved ? Colors.red : appbarcolor,
                            ),
                            label: Text(isSaved ? 'Saved' : 'Save'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isSaved
                                  ? Colors.red
                                  : appbarcolor,
                              side: BorderSide(color: appbarcolor),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Download All button with progress
                      ValueListenableBuilder<bool>(
                        valueListenable: _bulkBusy,
                        builder: (context, bulkBusy, _) {
                          final total = provider.videos.length;
                          final downloadedCount = provider.videos
                              .where((v) => _isDownloaded(v.id.value))
                              .length;
                          final remaining = total - downloadedCount;
                          final allDownloaded = hasTracks && remaining == 0;
                          return OutlinedButton.icon(
                            onPressed: (!hasTracks || bulkBusy || allDownloaded)
                                ? null
                                : () => _downloadAll(provider),
                            icon: bulkBusy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        appbarcolor,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    allDownloaded
                                        ? Icons.offline_pin
                                        : Icons.download_for_offline_rounded,
                                    color: allDownloaded
                                        ? Colors.green
                                        : appbarcolor,
                                  ),
                            label: bulkBusy
                                ? ValueListenableBuilder<int>(
                                    valueListenable: _bulkDone,
                                    builder: (context, done, __) {
                                      return ValueListenableBuilder<int>(
                                        valueListenable: _bulkTotal,
                                        builder: (context, bTotal, ___) {
                                          final t = bTotal == 0
                                              ? remaining
                                              : bTotal;
                                          return Text('Downloading $done/$t');
                                        },
                                      );
                                    },
                                  )
                                : Text(
                                    allDownloaded
                                        ? 'Downloaded'
                                        : remaining == total
                                        ? 'Download all'
                                        : 'Download all ($remaining left)',
                                  ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: allDownloaded
                                  ? Colors.green
                                  : appbarcolor,
                              side: BorderSide(
                                color: allDownloaded
                                    ? Colors.green
                                    : appbarcolor,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Optional linear progress below buttons
                ValueListenableBuilder<bool>(
                  valueListenable: _bulkBusy,
                  builder: (context, bulkBusy, _) {
                    if (!bulkBusy) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _bulkDone,
                        builder: (context, done, __) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _bulkTotal,
                            builder: (context, total, ___) {
                              final t = total == 0 ? 1 : total;
                              final value = (done / t).clamp(0.0, 1.0);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: value,
                                    backgroundColor: appbarcolor.withOpacity(
                                      0.2,
                                    ),
                                    color: appbarcolor,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Downloaded $done/$total',
                                    style: TextStyle(
                                      color: txtcolor.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosList(PlaylistProvider provider) {
    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              'Error loading playlist',
              style: TextStyle(color: Colors.red, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              provider.error!,
              style: TextStyle(color: txtcolor.withOpacity(0.8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadPlaylistVideos(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (provider.isLoading || provider.videos.isEmpty) {
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (context, index) => _buildSkeletonVideoTile(),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: provider.videos.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: txtcolor.withOpacity(0.1)),
      ),
      itemBuilder: (context, i) =>
          _buildVideoTile(provider, provider.videos[i], i + 1),
    );
  }

  Widget _buildVideoTile(
    PlaylistProvider provider,
    Video video,
    int trackNumber,
  ) {
    final track = StreamingData(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, busy, __) {
        final disabled = busy || _audio.isPreparing.value;
        final isDownloaded = _isDownloaded(track.videoId);
        return Opacity(
          opacity: disabled ? 0.6 : 1,
          child: AbsorbPointer(
            absorbing: disabled,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cardcolor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: bgcolor,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child:
                            (track.thumbnailUrl != null &&
                                track.thumbnailUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: track.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  width: 60,
                                  height: 60,
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.music_note,
                                  color: iconcolor.withOpacity(0.6),
                                ),
                              ),
                      ),
                      if (isDownloaded)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.offline_pin,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Offline',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                title: Text(
                  track.title,
                  style: TextStyle(
                    color: txtcolor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.author,
                      style: TextStyle(
                        color: txtcolor.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    if (video.duration != null)
                      Text(
                        _formatDuration(video.duration!),
                        style: TextStyle(
                          color: txtcolor.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                trailing: ValueListenableBuilder<Set<String>>(
                  valueListenable: _downloading,
                  builder: (context, downloading, _) {
                    final isBusyDownload = downloading.contains(track.videoId);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDownloaded)
                          const Icon(Icons.offline_pin, color: Colors.green),
                        const SizedBox(width: 8),
                        isBusyDownload
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    appbarcolor,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.download_rounded),
                                color: appbarcolor,
                                onPressed: () =>
                                    _onDownloadTrack(context, track),
                              ),
                        const SizedBox(width: 4),
                        // Play button with spinner for the track being started
                        ValueListenableBuilder<String?>(
                          valueListenable: _startingTrackId,
                          builder: (context, startingId, __) {
                            final isStartingThis =
                                startingId == track.videoId && _busy.value;
                            if (isStartingThis) {
                              return SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    appbarcolor,
                                  ),
                                ),
                              );
                            }
                            return IconButton(
                              icon: const Icon(Icons.play_arrow),
                              color: appbarcolor,
                              onPressed: () async {
                                if (busy || _audio.isPreparing.value) return;
                                _busy.value = true;
                                _startingTrackId.value = track.videoId;
                                try {
                                  // Prefer local playback if downloaded
                                  final local = _downloadsBox?.get(
                                    track.videoId,
                                  );
                                  if (local != null) {
                                    try {
                                      final data =
                                          jsonDecode(local)
                                              as Map<String, dynamic>;
                                      final filePath =
                                          data['filePath'] as String?;
                                      if (filePath != null &&
                                          File(filePath).existsSync()) {
                                        // Start loading offline track in background
                                        Future.microtask(() async {
                                          try {
                                            await _audio.stop();
                                            await _audio.loadPlaylist(
                                              [
                                                StreamingData(
                                                  videoId: track.videoId,
                                                  title: track.title,
                                                  artist: track.artist,
                                                  thumbnailUrl:
                                                      data['artPath']
                                                          as String? ??
                                                      track.thumbnailUrl,
                                                  duration: track.duration,
                                                  streamUrl: filePath,
                                                  isAvailable: true,
                                                  isLocal: true,
                                                ),
                                              ],
                                              initialIndex: 0,
                                              autoPlay: true,
                                              sourceType: 'OFFLINE',
                                              sourceName: 'Downloads',
                                            );
                                          } catch (e) {
                                            debugPrint(
                                              'Offline load failed: $e',
                                            );
                                          }
                                        });
                                        if (mounted) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  PlayerScreen(
                                                    title: track.title,
                                                    artist: track.artist,
                                                    imageUrl:
                                                        data['artPath']
                                                            as String? ??
                                                        track.thumbnailUrl,
                                                    duration: track.duration,
                                                  ),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                    } catch (_) {}
                                  }

                                  // Fallback: play from playlist (online)
                                  final playlist = provider.videos
                                      .map(
                                        (v) => StreamingData(
                                          videoId: v.id.value,
                                          title: v.title,
                                          artist: v.author,
                                          thumbnailUrl: v.thumbnails.highResUrl,
                                          duration: v.duration,
                                        ),
                                      )
                                      .toList();
                                  // Start online playlist load in background
                                  Future.microtask(() async {
                                    try {
                                      await _audio.stop();
                                      await _audio.loadPlaylist(
                                        playlist,
                                        initialIndex: trackNumber - 1,
                                        autoPlay: true,
                                        sourceType: 'PLAYLIST',
                                        sourceName: widget.playlistContent.name,
                                      );
                                    } catch (e) {
                                      debugPrint('Playlist load failed: $e');
                                    }
                                  });
                                  // Pre-cache image for the selected track
                                  if (track.thumbnailUrl != null &&
                                      track.thumbnailUrl!.isNotEmpty) {
                                    try {
                                      await ImageCacheService().preloadImage(
                                        track.thumbnailUrl!,
                                      );
                                    } catch (_) {}
                                  }
                                  if (mounted) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => PlayerScreen(
                                          title: track.title,
                                          artist: track.artist,
                                          imageUrl: track.thumbnailUrl,
                                          duration: track.duration,
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  _startingTrackId.value = null;
                                  if (mounted) _busy.value = false;
                                }
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                onTap: () async {
                  if (busy || _audio.isPreparing.value) return;
                  _busy.value = true;
                  _startingTrackId.value = track.videoId;
                  try {
                    final playlist = provider.videos
                        .map(
                          (v) => StreamingData(
                            videoId: v.id.value,
                            title: v.title,
                            artist: v.author,
                            thumbnailUrl: v.thumbnails.highResUrl,
                            duration: v.duration,
                          ),
                        )
                        .toList();
                    // Start playlist load in background
                    Future.microtask(() async {
                      try {
                        await _audio.stop();
                        await _audio.loadPlaylist(
                          playlist,
                          initialIndex: trackNumber - 1,
                          autoPlay: true,
                          sourceType: 'PLAYLIST',
                          sourceName: widget.playlistContent.name,
                        );
                      } catch (e) {
                        debugPrint('Playlist load failed: $e');
                      }
                    });
                    // Pre-cache image for the tapped track
                    if (track.thumbnailUrl != null &&
                        track.thumbnailUrl!.isNotEmpty) {
                      try {
                        await ImageCacheService().preloadImage(
                          track.thumbnailUrl!,
                        );
                      } catch (_) {}
                    }
                    if (mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PlayerScreen(
                            title: track.title,
                            artist: track.artist,
                            imageUrl: track.thumbnailUrl,
                            duration: track.duration,
                          ),
                        ),
                      );
                    }
                  } finally {
                    _startingTrackId.value = null;
                    if (mounted) _busy.value = false;
                  }
                },
              ),
            ),
          ), // close AbsorbPointer
        ); // close Opacity
      },
    );
  }

  Widget _buildSkeletonVideoTile() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cardcolor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: cardcolor.withOpacity(0.7),
          ),
        ),
        title: Container(
          height: 16,
          decoration: BoxDecoration(
            color: cardcolor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              height: 12,
              width: 100,
              decoration: BoxDecoration(
                color: cardcolor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 10,
              width: 60,
              decoration: BoxDecoration(
                color: cardcolor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        trailing: Icon(Icons.play_arrow, color: cardcolor.withOpacity(0.7)),
      ),
    );
  }

  Future<void> _onDownloadTrack(
    BuildContext context,
    StreamingData track, {
    bool silent = false,
  }) async {
    final videoId = track.videoId;
    if (videoId.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No track id to download')),
        );
      }
      return;
    }

    _setDownloading(videoId, true);
    try {
      // Request storage permission on Android
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

      final safeTitle = _sanitizeFileName(track.title);

      // Fetch stream URL via API
      final api = Api();
      final url = await api.getDownloadUrl(videoId);
      final meta = api.getMetadata;

      // Decide file extension from URL/mime (Explode often returns webm/opus)
      final ext = _inferAudioExtensionFromUrl(url);
      final filePath = '${musicDir.path}/$safeTitle$ext';
      final file = File(filePath);

      // Download bytes
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        throw Exception('Failed to download audio');
      }
      await file.writeAsBytes(resp.bodyBytes);

      // Save artwork
      String? artPath;
      if ((meta.thumbnail).isNotEmpty) {
        try {
          final artResp = await http.get(Uri.parse(meta.thumbnail));
          if (artResp.statusCode == 200) {
            final artFile = File('${musicDir.path}/$safeTitle.jpg');
            await artFile.writeAsBytes(artResp.bodyBytes);
            artPath = artFile.path;
          }
        } catch (_) {}
      }

      // Store metadata in Hive
      final metaJson = {
        'videoId': videoId,
        'title': meta.title.isNotEmpty ? meta.title : track.title,
        'artist': track.artist,
        'artPath': artPath,
        'imageUrl': meta.thumbnail,
        'filePath': file.path,
        'downloadedAt': DateTime.now().toIso8601String(),
      };
      await _downloadsBox?.put(videoId, jsonEncode(metaJson));

      if (!mounted) return;
      setState(() {}); // refresh offline indicator
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded \'${track.title}\'')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      _setDownloading(videoId, false);
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

  Future<void> _downloadAll(PlaylistProvider provider) async {
    if (_bulkBusy.value) return;

    final videos = provider.videos;
    if (videos.isEmpty) return;

    // Compute remaining items
    final toDownload = <StreamingData>[];
    for (final v in videos) {
      if (!_isDownloaded(v.id.value)) {
        toDownload.add(
          StreamingData(
            videoId: v.id.value,
            title: v.title,
            artist: v.author,
            thumbnailUrl: v.thumbnails.highResUrl,
            duration: v.duration,
          ),
        );
      }
    }
    if (toDownload.isEmpty) return;

    _bulkBusy.value = true;
    _bulkDone.value = 0;
    _bulkTotal.value = toDownload.length;

    // Optional: confirm with user
    if (mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: cardcolor,
            title: const Text('Download all?'),
            content: Text(
              'Download ${toDownload.length} tracks for offline playback?\nThis may use data and storage.',
              style: TextStyle(color: txtcolor.withOpacity(0.9)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Download'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        _bulkBusy.value = false;
        return;
      }
    }

    int success = 0;
    int failed = 0;

    try {
      for (final t in toDownload) {
        await _onDownloadTrack(context, t, silent: true);
        // Check box for success
        if (_isDownloaded(t.videoId)) {
          success += 1;
        } else {
          failed += 1;
        }
        _bulkDone.value = _bulkDone.value + 1;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Playlist downloaded: $success succeeded${failed > 0 ? ', $failed failed' : ''}.',
            ),
          ),
        );
      }
    } finally {
      _bulkBusy.value = false;
      // Trigger refresh to update badges/indicators
      if (mounted) setState(() {});
    }
  }

  String _sanitizeFileName(String s) {
    final illegal = RegExp(r'[\\/:*?"<>|]');
    return s.replaceAll(illegal, '_');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
