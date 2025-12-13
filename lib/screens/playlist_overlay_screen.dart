/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:convert';
import 'dart:io';

import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
//  for downloads/offline storage ie when one downloads a track for offline listening not  devices files.
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
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
import 'package:sautifyv2/widgets/playlist_loading_progress.dart';
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
  Box<String>? _downloadsBox;
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

  // Downloads box is used only to prefer offline playback if a track already
  // exists locally. There is no download UI on this screen.

  @override
  void dispose() {
    _busy.dispose();
    _startingTrackId.dispose();
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
                  Positioned.fill(
                    child: Column(
                      children: [
                        _buildHeader(context),
                        _buildPlaylistInfo(context, playlistProvider),
                        Expanded(child: _buildVideosList(playlistProvider)),
                      ],
                    ),
                  ),
                  // Global playlist loading progress overlay (auto-hides when done)
                  const Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: PlaylistLoadingProgress(),
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
          /*    Expanded(
            child: Text(
              'Playlist',
              style: TextStyle(
                color: txtcolor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),*/
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
      //  height: MediaQuery.of(context).size.height * 0.4,
      child: Column(
        children: [
          // Playlist thumbnail
          M3Container.square(
            width: 150,
            height: 150,

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

          const SizedBox(height: 16),

          // Playlist details
          Column(
            // crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.playlistContent.name,
                style: TextStyle(
                  color: txtcolor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 10,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.4,
                        child: Text(
                          widget.playlistContent.artistName,
                          style: TextStyle(
                            color: txtcolor.withAlpha((255 * 0.7).toInt()),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Play + Save
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Consumer<LibraryProvider>(
                          builder: (context, lib, _) {
                            final isSaved =
                                playlistId.isNotEmpty &&
                                lib.getPlaylists().any(
                                  (p) => p.id == playlistId,
                                );
                            return IconButton(
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
                                        final tracksFull = provider.videos
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
                                        final tracks = tracksFull.length > 25
                                            ? tracksFull.sublist(0, 25)
                                            : tracksFull;
                                        final saved = SavedPlaylist(
                                          id: playlistId,
                                          title: widget.playlistContent.name,
                                          artworkUrl: widget
                                              .playlistContent
                                              .thumbnailUrl,
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
                                isSaved
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isSaved ? Colors.red : appbarcolor,
                              ),
                              // label: Text(isSaved ? 'Saved' : 'Save'),
                              /*  style: OutlinedButton.styleFrom(
                                foregroundColor: isSaved ? Colors.red : appbarcolor,
                                side: BorderSide(color: appbarcolor),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),*/
                            );
                          },
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          onPressed: () {},
                          icon: Icon(
                            Icons.download_for_offline,
                            color: appbarcolor,
                          ),
                        ),
                        // Removed Download All button
                        //shuffle button
                        IconButton(
                          onPressed: () {},
                          icon: Icon(Icons.shuffle, color: appbarcolor),
                        ),
                      ],
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _busy,
                      builder: (context, busy, __) {
                        final disabled =
                            !hasTracks || busy || _audio.isPreparing.value;
                        return IconButton(
                          onPressed: disabled
                              ? null
                              : () async {
                                  if (busy || _audio.isPreparing.value) return;
                                  _busy.value = true;
                                  try {
                                    final playlistFull = provider.videos
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
                                    final playlist = playlistFull.length > 25
                                        ? playlistFull.sublist(0, 25)
                                        : playlistFull;
                                    // Use new fingerprint-aware replacePlaylist
                                    await _audio.replacePlaylist(
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
                              : Icon(Icons.play_arrow, color: iconcolor),
                          /*  label: disabled
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: ExpressiveLoadingIndicator(
                                    constraints: BoxConstraints(
                                      maxWidth: 30,
                                      maxHeight: 30,
                                      minHeight: 15,
                                      minWidth: 15,
                                    ),
                                    color: appbarcolor.withAlpha(200),
                                  ),
                                )
                              : const Text('Play'),
                              */
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appbarcolor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Removed download progress section
            ],
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
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, index) => _buildSkeletonVideoTile(),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: provider.videos.length,
      /*separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: txtcolor.withOpacity(0.1)),
      ),*/
      itemBuilder: (context, i) => _buildVideoTile(
        provider,
        provider.videos[i],
        i + 1,
        provider.videos.length,
      ),
    );
  }

  Widget _buildVideoTile(
    PlaylistProvider provider,
    Video video,
    int trackNumber,
    int length,
  ) {
    final track = StreamingData(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, busy, __) {
        final disabled = busy || _audio.isPreparing.value;
        return AbsorbPointer(
          absorbing: disabled,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: bgcolor.withAlpha(50),
              borderRadius: BorderRadius.vertical(
                top: trackNumber == 0
                    ? const Radius.circular(33)
                    : const Radius.circular(6),
                bottom: trackNumber == length - 1
                    ? const Radius.circular(33)
                    : const Radius.circular(6),
              ),
            ),
            /*


             ValueListenableBuilder<String?>(
               valueListenable: _startingTrackId,
               builder: (context, startingId, _) {
                 final isStartingThis =
                     startingId == track.videoId && _busy.value;
                 if (isStartingThis) {
                   return SizedBox(
                     width: 24,
                     height: 24,
                     child: ExpressiveLoadingIndicator(color: appbarcolor),
                   );
                 }
                 return Container(
                   decoration: BoxDecoration(
                     color: appbarcolor.withAlpha(200),
                     borderRadius: BorderRadius.circular(100),
                   ),
                   child: Center(
                     child: IconButton(
                       icon: const Icon(Icons.play_arrow, color: Colors.black),
                       color: appbarcolor,
                       onPressed: () async {
                         if (busy || _audio.isPreparing.value) return;
                         _busy.value = true;
                         _startingTrackId.value = track.videoId;
                         try {
                           // Prefer local playback if metadata exists
                           final local = _downloadsBox?.get(track.videoId);
                           if (local != null) {
                             try {
                               final data =
                                   jsonDecode(local) as Map<String, dynamic>;
                               final filePath = data['filePath'] as String?;
                               if (filePath != null &&
                                   File(filePath).existsSync()) {
                                 // Load offline track
                                 try {
                                   await _audio.stop();
                                   await _audio.loadPlaylist(
                                     [
                                       StreamingData(
                                         videoId: track.videoId,
                                         title: track.title,
                                         artist: track.artist,
                                         thumbnailUrl:
                                             data['artPath'] as String? ??
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
                                   debugPrint('Offline load failed: $e');
                                 }
             
                                 if (mounted) {
                                   Navigator.of(context).push(
                                     MaterialPageRoute(
                                       builder: (context) => PlayerScreen(
                                         title: track.title,
                                         artist: track.artist,
                                         imageUrl:
                                             data['artPath'] as String? ??
                                             track.thumbnailUrl,
                                         duration: track.duration,
                                         sourceType: 'OFFLINE',
                                         sourceName: 'Downloads',
                                       ),
                                     ),
                                   );
                                 }
                                 return;
                               }
                             } catch (_) {}
                           }
             
                           // Fallback to online playlist
                           final playlistFull = provider.videos
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
                           List<StreamingData> playlist;
                           int cappedIndex;
                           if (playlistFull.length > 25) {
                             int start = (trackNumber - 1) - 12;
                             if (start < 0) start = 0;
                             if (start > playlistFull.length - 25)
                               start = playlistFull.length - 25;
                             playlist = playlistFull.sublist(
                               start,
                               start + 25,
                             );
                             cappedIndex = (trackNumber - 1) - start;
                           } else {
                             playlist = playlistFull;
                             cappedIndex = trackNumber - 1;
                           }
             
                           // Start loading the playlist (await it to ensure it starts)
                           try {
                             await _audio.stop();
                             // Start loading but don't await completion - let progress tracking show
                             _audio.loadPlaylist(
                               playlist,
                               initialIndex: cappedIndex,
                               autoPlay: true,
                               sourceType: 'PLAYLIST',
                               sourceName: widget.playlistContent.name,
                             );
                           } catch (e) {
                             debugPrint('Playlist load failed: $e');
                           }
             
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
                                   playlist: playlist,
                                   initialIndex: cappedIndex,
                                   sourceType: 'PLAYLIST',
                                   sourceName: widget.playlistContent.name,
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
                 );
               },
             ),
           ),*/

            /*

 ValueListenableBuilder<String?>(
               valueListenable: _startingTrackId,
               builder: (context, startingId, _) {
                 final isStartingThis =
                     startingId == track.videoId && _busy.value;
                 if (isStartingThis) {
                   return SizedBox(
                     width: 24,
                     height: 24,
                     child: ExpressiveLoadingIndicator(color: appbarcolor),
                   );
                 }
                 return Container(
                   decoration: BoxDecoration(
                     color: appbarcolor.withAlpha(200),
                     borderRadius: BorderRadius.circular(100),
                   ),
           */
            child: ValueListenableBuilder<String?>(
              valueListenable: _startingTrackId,
              builder: (context, startingId, _) {
                final isStartingThis =
                    startingId == track.videoId && _busy.value;
                if (isStartingThis) {
                  return SizedBox(
                    width: 24,
                    height: 24,
                    child: ExpressiveLoadingIndicator(color: appbarcolor),
                  );
                }
                return GestureDetector(
                  onTap: () async {
                    if (busy || _audio.isPreparing.value) return;
                    _busy.value = true;
                    _startingTrackId.value = track.videoId;
                    try {
                      // Prefer local playback if metadata exists
                      final local = _downloadsBox?.get(track.videoId);
                      if (local != null) {
                        try {
                          final data =
                              jsonDecode(local) as Map<String, dynamic>;
                          final filePath = data['filePath'] as String?;
                          if (filePath != null && File(filePath).existsSync()) {
                            // Load offline track
                            try {
                              await _audio.stop();
                              await _audio.loadPlaylist(
                                [
                                  StreamingData(
                                    videoId: track.videoId,
                                    title: track.title,
                                    artist: track.artist,
                                    thumbnailUrl:
                                        data['artPath'] as String? ??
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
                              debugPrint('Offline load failed: $e');
                            }

                            if (mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => PlayerScreen(
                                    title: track.title,
                                    artist: track.artist,
                                    imageUrl:
                                        data['artPath'] as String? ??
                                        track.thumbnailUrl,
                                    duration: track.duration,
                                    sourceType: 'OFFLINE',
                                    sourceName: 'Downloads',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                        } catch (_) {}
                      }

                      // Fallback to online playlist
                      final playlistFull = provider.videos
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
                      List<StreamingData> playlist;
                      int cappedIndex;
                      if (playlistFull.length > 25) {
                        int start = (trackNumber - 1) - 12;
                        if (start < 0) start = 0;
                        if (start > playlistFull.length - 25) {
                          start = playlistFull.length - 25;
                        }
                        playlist = playlistFull.sublist(start, start + 25);
                        cappedIndex = (trackNumber - 1) - start;
                      } else {
                        playlist = playlistFull;
                        cappedIndex = trackNumber - 1;
                      }

                      // Start loading the playlist (await it to ensure it starts)
                      try {
                        await _audio.stop();
                        // Start loading but don't await completion - let progress tracking show
                        _audio.loadPlaylist(
                          playlist,
                          initialIndex: cappedIndex,
                          autoPlay: true,
                          sourceType: 'PLAYLIST',
                          sourceName: widget.playlistContent.name,
                        );
                      } catch (e) {
                        debugPrint('Playlist load failed: $e');
                      }

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
                              playlist: playlist,
                              initialIndex: cappedIndex,
                              sourceType: 'PLAYLIST',
                              sourceName: widget.playlistContent.name,
                            ),
                          ),
                        );
                      }
                    } finally {
                      _startingTrackId.value = null;
                      if (mounted) _busy.value = false;
                    }
                  },

                  /// Video song Tile UI
                  child: ListTile(
                    /* contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),*/
                    leading: SizedBox(
                      width: 56,
                      height: 56,
                      child: M3Container.c7SidedCookie(
                        width: 56,
                        height: 56,
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
                                        placeholder: M3Container.c7SidedCookie(
                                          color: bgcolor.withAlpha(50),
                                          child: ExpressiveLoadingIndicator(
                                            color: appbarcolor.withAlpha(155),
                                            constraints: BoxConstraints(
                                              maxHeight: 100,
                                              maxWidth: 100,
                                              minHeight: 50,
                                              minWidth: 50,
                                            ),
                                          ),
                                        ),
                                        fit: BoxFit.cover,
                                        width: 56,
                                        height: 56,
                                      ),
                                    )
                                  : Center(
                                      child: M3Container.c7SidedCookie(
                                        color: bgcolor.withAlpha(50),
                                        child: Icon(
                                          Icons.music_note,
                                          color: iconcolor.withAlpha(155),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    title: Text(
                      track.title,
                      style: TextStyle(
                        color: txtcolor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      video.author,
                      style: TextStyle(
                        color: txtcolor.withAlpha(178),
                        fontSize: 12,
                      ),
                    ),
                    trailing: (video.duration != null)
                        ? Text(
                            _formatDuration(video.duration!),
                            style: TextStyle(
                              color: txtcolor.withAlpha((255 * 0.5).toInt()),
                              fontSize: 12,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              },
            ),

            //////////////////////////////
          ),
        );
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

  // Removed download actions (per-item and bulk) from this screen.

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
