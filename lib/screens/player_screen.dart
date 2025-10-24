// ignore_for_file: deprecated_member_use

/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
// Import for ScrollDirection used in NotificationListener
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_audio_output/flutter_audio_output.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:marquee/marquee.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/screens/current_playlist_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/widgets/playlist_loading_progress.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final String artist;
  final String? imageUrl;
  final Duration? duration;
  final String? videoId;
  final List<StreamingData>? playlist;
  final int? initialIndex;
  // New: where playback originates
  final String?
  sourceType; // PLAYLIST, ALBUM, SEARCH, RECENTS, FAVORITES, QUEUE
  final String? sourceName; // e.g., playlist/album name

  const PlayerScreen({
    super.key,
    required this.title,
    required this.artist,
    this.imageUrl,
    this.duration,
    this.videoId,
    this.playlist,
    this.initialIndex,
    this.sourceType,
    this.sourceName,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayerService _audioService;
  bool isLiked = false;
  StreamSubscription<StreamingData?>? _trackSub;
  AudioInput? _currentOutput;
  //  List<AudioInput> _availableDevices = [];

  // Dynamic background colors based on current artwork
  List<Color> _bgColors = [bgcolor.withAlpha(200), bgcolor, Colors.black];
  String? _lastArtworkUrl;

  // Lyrics state
  final YTMusic _ytmusic = YTMusic();
  bool _ytReady = false;
  bool _showLyrics = false;
  bool _lyricsLoading = false;
  String? _lyricsError;
  String? _lyricsSource;
  String? _lyricsForVideoId;
  final ScrollController _lyricsScrollController = ScrollController();
  List<_LyricLine> _lyrics = <_LyricLine>[];
  // Cache lyrics by the original current videoId to avoid repeated network calls
  final Map<String, List<_LyricLine>> _lyricsCache =
      <String, List<_LyricLine>>{};
  // Auto-scroll state
  int _activeLyricIndex = -1;
  bool _userScrollingLyrics = false;
  DateTime _lastAutoScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const double _lyricRowApproxHeight = 32.0;

  @override
  void initState() {
    super.initState();
    _audioService = AudioPlayerService(); // This gets the singleton instance

    // Load playlist/track only if audio service is not already loading something
    // and doesn't have the expected content
    final bool serviceHasContent = _audioService.playlist.isNotEmpty;
    final bool serviceIsPreparing = _audioService.isPreparing.value;

    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      // Only load if service doesn't already have this playlist or isn't preparing it
      if (!serviceIsPreparing && !serviceHasContent) {
        Future.microtask(_loadPlaylist);
      }
    } else if (widget.videoId != null &&
        !serviceHasContent &&
        !serviceIsPreparing) {
      Future.microtask(_loadSingleTrack);
    }

    // Keep like state in sync with current track
    _trackSub = _audioService.currentTrackStream.listen((track) async {
      final vid = track?.videoId ?? widget.videoId;
      if (vid == null || vid.isEmpty) {
        if (mounted) setState(() => isLiked = false);
        return;
      }
      final fav = await LibraryStore.isFavorite(vid);
      if (mounted) setState(() => isLiked = fav);
    });
    _initAudioOutput();
  }

  Future<void> _initAudioOutput() async {
    // Set up listener for audio device changes
    FlutterAudioOutput.setListener(() async {
      await _refreshAudioDevices();
    });

    // Initial load
    await _refreshAudioDevices();
  }

  Future<void> _refreshAudioDevices() async {
    try {
      final current = await FlutterAudioOutput.getCurrentOutput();
      // final available = await FlutterAudioOutput.getAvailableInputs();

      setState(() {
        _currentOutput = current;
        //  _availableDevices = available;
      });
    } catch (e) {
      throw Exception('Error refreshing audio devices: $e');
      //print('Error refreshing audio devices: $e');
    }
  }

  void _loadPlaylist() async {
    try {
      final full = widget.playlist!;
      final idx = widget.initialIndex ?? 0;
      List<StreamingData> capped;
      int cappedIdx;
      if (full.length > 25) {
        int start = idx - 12;
        if (start < 0) start = 0;
        if (start > full.length - 25) start = full.length - 25;
        capped = full.sublist(start, start + 25);
        cappedIdx = idx - start;
      } else {
        capped = full;
        cappedIdx = idx;
      }
      await _audioService.loadPlaylist(
        capped,
        initialIndex: cappedIdx,
        autoPlay: true,
        sourceType: widget.sourceType ?? 'QUEUE',
        sourceName: widget.sourceName,
      );
    } catch (e) {
      throw Exception('Error loading playlist: $e');
    }
  }

  void _loadSingleTrack() async {
    if (widget.videoId == null) return;

    try {
      final track = StreamingData(
        videoId: widget.videoId!,
        title: widget.title,
        artist: widget.artist,
        thumbnailUrl: widget.imageUrl,
        duration: widget.duration,
      );

      await _audioService.loadPlaylist(
        [track],
        autoPlay: true,
        sourceType: widget.sourceType ?? 'QUEUE',
        sourceName: widget.sourceName,
      );
    } catch (e) {
      print('Error loading single track: $e');
    }
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    FlutterAudioOutput.removeListener();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    final playerState = _audioService.player.playerState;
    if (playerState.playing) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgcolor,
      body: StreamBuilder<TrackInfo>(
        stream: _audioService.trackInfoStream,
        builder: (context, infoSnap) {
          final info = infoSnap.data;

          // Fallbacks to initial widget props when stream not ready
          final currentTitle = info?.title.isNotEmpty == true
              ? info!.title
              : widget.title;
          final currentArtist = info?.artist.isNotEmpty == true
              ? info!.artist
              : widget.artist;
          final artworkUrl = info?.thumbnailUrl ?? widget.imageUrl;
          final duration = info?.duration ?? widget.duration;
          final position = info?.position ?? Duration.zero;

          // Update gradient palette when artwork changes
          if (artworkUrl != null && artworkUrl != _lastArtworkUrl) {
            _lastArtworkUrl = artworkUrl;
            _updatePaletteFromArtwork(artworkUrl);
          }

          return SafeArea(
            child: Stack(
              children: [
                // Background gradient base driven by palette
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _bgColors,
                    ),
                  ),
                ),

                // Reactive blurred album-art background with smooth cross-fade
                if (artworkUrl != null)
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      child: Stack(
                        key: ValueKey(artworkUrl),
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: artworkUrl,
                            fit: BoxFit.cover,
                            errorWidget: Container(color: Colors.black),
                          ),
                          BackdropFilter(
                            // Lower blur radius for performance while keeping the look
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: Container(
                              color: Colors.black.withAlpha(100),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Main content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        // Top bar
                        _buildTopBar(info),

                        const SizedBox(height: 40),

                        // Album art with optional lyrics overlay and toggle button
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              RepaintBoundary(
                                child: _buildAlbumArt(artworkUrl),
                              ),
                              if (info?.hasTrack == true)
                                /* Positioned(
                                  right: 8,
                                  top: 8,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      tooltip: 'Lyrics',
                                      icon: Icon(
                                        _showLyrics
                                            ? Icons.lyrics
                                            : Icons.lyrics_outlined,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        if (_showLyrics) {
                                          setState(() => _showLyrics = false);
                                        } else {
                                          _loadLyricsForCurrentSong();
                                        }
                                      },
                                    ),
                                  ),
                                ),*/
                                if (_showLyrics)
                                  Positioned.fill(
                                    child: _buildLyricsOverlay(info),
                                  ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Song info
                        _buildSongInfo(currentTitle, currentArtist),

                        const SizedBox(height: 30),

                        // Progress bar
                        _buildProgressBar(duration, position),

                        const SizedBox(height: 40),

                        // Control buttons (uses info for loop/shuffle/isPlaying)
                        _buildControlButtons(info),

                        const SizedBox(height: 30),

                        // Bottom controls
                        _buildBottomControls(currentTitle),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),

                // Playlist loading progress overlay
                Positioned(
                  top: 80,
                  left: 0,
                  right: 0,
                  child: const PlaylistLoadingProgress(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _updatePaletteFromArtwork(String url) async {
    try {
      final cache = ImageCacheService();
      final bytes =
          await cache.getCachedImage(url) ?? await _fetchImageBytes(url);
      if (bytes == null || bytes.isEmpty) return;

      // Slight defer to avoid blocking transition to player screen
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Decode with codec at a reduced size for speed (downscale to ~128px longest side)
      final codec = await instantiateImageCodec(
        bytes,
        targetHeight: 128,
        targetWidth: 128,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final raw = byteData.buffer.asUint32List();
      // Convert RGBA -> ARGB (material_color_utilities expects ARGB int format)
      final pixels = List<int>.generate(raw.length, (i) {
        final v = raw[i];
        final r = v & 0xFF;
        final g = (v >> 8) & 0xFF;
        final b = (v >> 16) & 0xFF;
        final a = (v >> 24) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
      });

      // Quantize colors using material_color_utilities (instance call)
      final quantizerResult = await mcu.QuantizerCelebi().quantize(pixels, 64);
      final ranked = mcu.Score.score(quantizerResult.colorToCount);

      // Extract top colors (fallback chain ensures stability)
      int? primaryArgb = ranked.isNotEmpty ? ranked.first : null;
      int? secondaryArgb = ranked.length > 1 ? ranked[1] : null;

      Color primary = primaryArgb != null
          ? Color(primaryArgb).withOpacity(0.85)
          : const Color(0xFF222222).withOpacity(0.85);
      Color secondary = secondaryArgb != null
          ? Color(secondaryArgb).withOpacity(0.8)
          : const Color(0xFF111111).withOpacity(0.8);

      // Ensure sufficient contrast between first two; if too close, darken second
      if (_relativeLuminance(primary) - _relativeLuminance(secondary) < 0.07) {
        secondary = _darken(secondary, 0.2);
      }

      final newColors = <Color>[primary, secondary, Colors.black];

      if (!mounted) return;
      setState(() => _bgColors = newColors);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _bgColors = [bgcolor.withAlpha(200), bgcolor, Colors.black],
      );
    }
  }

  // Fetch remote image bytes (fallback if not in cache)
  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(resp);
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}
    return null;
  }

  // Simple luminance approximation for contrast heuristic
  double _relativeLuminance(Color c) {
    return 0.2126 * c.red / 255 +
        0.7152 * c.green / 255 +
        0.0722 * c.blue / 255;
  }

  Color _darken(Color c, double amount) {
    final f = (1 - amount).clamp(0.0, 1.0);
    return Color.fromARGB(
      c.alpha,
      (c.red * f).round(),
      (c.green * f).round(),
      (c.blue * f).round(),
    );
  }

  Widget _buildTopBar(TrackInfo? info) {
    final type = (info?.sourceType ?? 'QUEUE').toUpperCase();
    final typeLabel = 'PLAYING FROM $type';

    String nameLabel;
    if (info?.sourceName != null && info!.sourceName!.isNotEmpty) {
      nameLabel = info.sourceName!;
    } else {
      switch (type) {
        case 'FAVORITES':
          nameLabel = 'Liked Songs';
          break;
        case 'RECENTS':
          nameLabel = 'Recently Played';
          break;
        case 'SEARCH':
          nameLabel = 'Search';
          break;
        case 'QUEUE':
          nameLabel = 'Queue';
          break;
        default:
          nameLabel = '';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.keyboard_arrow_down, color: iconcolor, size: 32),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: txtcolor.withAlpha(180),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              if (nameLabel.isNotEmpty)
                Text(
                  nameLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: txtcolor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 48),
        /* IconButton(
          onPressed: () {},
          icon: Icon(Icons.more_horiz, color: iconcolor, size: 28),
        ),*/
      ],
    );
  }

  Widget _buildAlbumArt(String? imageUrl) {
    final isLocalImage =
        imageUrl != null &&
        (imageUrl.startsWith('file://') ||
            imageUrl.startsWith('/') ||
            imageUrl.contains('\\'));
    return Center(
      child: Container(
        width: 320,
        height: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(100),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageUrl != null
              ? (isLocalImage
                    ? Image.file(
                        File(imageUrl.replaceFirst('file://', '')),
                        fit: BoxFit.cover,
                        width: 320,
                        height: 320,
                        errorBuilder: (context, _, __) =>
                            _buildDefaultAlbumArt(),
                      )
                    : CachedNetworkImage(
                        placeholder: M3Container.c7SidedCookie(
                          child: LoadingIndicatorM3E(
                            containerColor: bgcolor.withAlpha(100),
                            color: appbarcolor.withAlpha(155),
                            constraints: BoxConstraints(
                              maxWidth: 100,
                              maxHeight: 100,
                              minWidth: 80,
                              minHeight: 80,
                            ),
                            polygons: [
                              MaterialShapes.sunny,
                              MaterialShapes.cookie9Sided,
                              MaterialShapes.pill,
                            ],
                          ),
                        ),
                        imageUrl: imageUrl,
                        borderRadius: BorderRadius.circular(12),
                        fit: BoxFit.cover,
                        width: 320,
                        height: 320,
                        errorWidget: _buildDefaultAlbumArt(),
                      ))
              : _buildDefaultAlbumArt(),
        ),
      ),
    );
  }

  Widget _buildDefaultAlbumArt() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00FFFF), // Cyan
            const Color(0xFFFFFF00), // Yellow
            const Color(0xFF0080FF), // Blue
            cardcolor,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note, size: 80, color: txtcolor.withAlpha(200)),
      ),
    );
  }

  Widget _buildSongInfo(String title, String artist) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 90,
                height: 30,
                child: Marquee(
                  // rtl: true,
                  text: title,
                  startAfter: Duration(seconds: 20),
                  pauseAfterRound: Duration(seconds: 30),
                  style: TextStyle(
                    color: txtcolor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  // maxLines: 2,
                  //   overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist,
                style: TextStyle(
                  color: txtcolor.withAlpha(180),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            final t =
                _audioService.currentTrack ??
                (widget.videoId != null
                    ? StreamingData(
                        videoId: widget.videoId!,
                        title: widget.title,
                        artist: widget.artist,
                        thumbnailUrl: widget.imageUrl,
                        duration: widget.duration,
                      )
                    : null);

            if (t == null || t.videoId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot favorite: missing track ID'),
                ),
              );
              return;
            }

            await LibraryStore.toggleFavorite(t);

            // Optimistically invert and then verify from storage
            setState(() => isLiked = !isLiked);
            final fav = await LibraryStore.isFavorite(t.videoId);
            if (mounted) setState(() => isLiked = fav);
          },
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border_rounded,
            color: isLiked ? Colors.red : iconcolor,
            size: 28,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(Duration? duration, Duration position) {
    final d = duration ?? const Duration(minutes: 3, seconds: 30);
    final value = d.inMilliseconds > 0
        ? position.inMilliseconds / d.inMilliseconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: txtcolor,
            inactiveTrackColor: txtcolor.withAlpha(50),
            thumbColor: txtcolor,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: (newValue) {
              final newPosition = Duration(
                milliseconds: (d.inMilliseconds * newValue).round(),
              );
              _audioService.seek(newPosition);
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: TextStyle(color: txtcolor.withAlpha(180), fontSize: 12),
            ),
            Text(
              _formatDuration(d),
              style: TextStyle(color: txtcolor.withAlpha(180), fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlButtons(TrackInfo? info) {
    final isShuffled = info?.isShuffleEnabled ?? false;
    final loopMode = info?.loopMode ?? 'off';
    final isRepeating = loopMode != 'off';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle button
        IconButton(
          onPressed: () {
            _audioService.setShuffleModeEnabled(!isShuffled);
          },
          icon: Icon(
            Icons.shuffle,
            color: isShuffled ? appbarcolor : iconcolor.withAlpha(180),
            size: 24,
          ),
        ),
        // Previous button
        IconButton(
          onPressed: () {
            _audioService.skipToPrevious();
          },
          icon: Icon(Icons.skip_previous, color: iconcolor, size: 32),
        ),
        // Play/Pause button
        ValueListenableBuilder<bool>(
          valueListenable: _audioService.isPreparing,
          builder: (context, preparing, _) {
            return StreamBuilder<PlayerState>(
              stream: _audioService.playerStateStream,
              builder: (context, snapshot) {
                final playerState = snapshot.data;
                // Prefer engine state for 'playing' for immediacy; fallback to info
                final effectivePlaying =
                    playerState?.playing ?? (info?.isPlaying ?? false);
                final processing = playerState?.processingState;
                final engineLoading =
                    processing == ProcessingState.loading ||
                    processing == ProcessingState.buffering;
                // Show loading only when NOT playing and either preparing or engine is loading
                final isLoading =
                    (!effectivePlaying) && (preparing || engineLoading);

                return IconButton(
                  onPressed: isLoading ? null : _togglePlayPause,
                  icon: isLoading
                      ? SizedBox(
                          width: 32,
                          height: 32,
                          child: LoadingIndicatorM3E(
                            containerColor: bgcolor.withAlpha(100),
                            color: appbarcolor.withAlpha(155),
                            polygons: [
                              MaterialShapes.sunny,
                              MaterialShapes.cookie9Sided,
                              MaterialShapes.pill,
                            ],
                          ),
                        )
                      : Icon(
                          effectivePlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                );
              },
            );
          },
        ),
        // Next button
        IconButton(
          onPressed: () {
            _audioService.skipToNext();
          },
          icon: Icon(Icons.skip_next, color: iconcolor, size: 32),
        ),
        // Repeat button
        IconButton(
          onPressed: () {
            final newMode = loopMode == 'off'
                ? LoopMode.all
                : (loopMode == 'all' ? LoopMode.one : LoopMode.off);
            _audioService.setLoopMode(newMode);
          },
          icon: Icon(
            loopMode == 'one' ? Icons.repeat_one : Icons.repeat,
            color: isRepeating ? appbarcolor : iconcolor.withAlpha(180),
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardcolor.withAlpha(50),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: IconButton(
              tooltip: 'Lyrics',
              icon: Icon(
                _showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                color: Colors.white,
              ),
              onPressed: () {
                if (_showLyrics) {
                  setState(() => _showLyrics = false);
                } else {
                  _loadLyricsForCurrentSong();
                }
              },
            ),
          ),
        ),
        /* IconButton(
          onPressed: () {},
          icon: Icon(Icons.devices, color: iconcolor.withAlpha(180), size: 24),
        ),*/
        Row(
          children: [
            //Icon(Icons.headphones, color: appbarcolor, size: 16),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              height: 16,
              child: Marquee(
                text: ' Sautify Playing $title.',
                startAfter: Duration(seconds: 3),
                pauseAfterRound: Duration(seconds: 2),
                //  curve: Curves.linear,
                style: TextStyle(
                  color: appbarcolor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: cardcolor.withAlpha(50),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: IconButton(
              onPressed: () {
                _navigateToCurrentPlaylist(context);
              },
              icon: Icon(
                Icons.queue_music,
                color: iconcolor.withAlpha(180),
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToCurrentPlaylist(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CurrentPlaylistScreen(audioService: _audioService),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _ensureYtReady() async {
    if (_ytReady) return;
    try {
      await _ytmusic.initialize();
      _ytReady = true;
    } catch (e) {
      debugPrint('YTMusic init failed: $e');
    }
  }

  Future<void> _loadLyricsForCurrentSong() async {
    final vid = _audioService.currentTrack?.videoId ?? widget.videoId;
    if (vid == null || vid.isEmpty) {
      setState(() {
        _lyricsError = 'No current song';
        _showLyrics = true;
        _lyrics = [];
      });
      return;
    }

    // Serve from cache if present
    final cached = _lyricsCache[vid];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _lyricsError = null;
        _lyricsForVideoId = vid;
        _lyrics = cached;
        _showLyrics = true;
        _lyricsLoading = false;
      });
      return;
    }

    if (_lyricsForVideoId == vid && _lyrics.isNotEmpty) {
      setState(() {
        _lyricsError = null;
        _showLyrics = true;
      });
      return;
    }

    setState(() {
      _lyricsLoading = true;
      _lyricsError = null;
      _lyrics = [];
      _showLyrics = true;
    });

    await _ensureYtReady();
    try {
      // 1) Try timed lyrics for the current videoId
      final synclyrics = await _ytmusic.getTimedLyrics(vid);
      _lyricsSource = synclyrics?.sourceMessage;

      final lines = <_LyricLine>[];
      if (synclyrics != null && synclyrics.timedLyricsData.isNotEmpty) {
        for (final l in synclyrics.timedLyricsData) {
          final text = (l.lyricLine ?? '').toString();
          final start = l.cueRange?.startTimeMilliseconds ?? 0;
          final end = l.cueRange?.endTimeMilliseconds ?? (start + 2000);
          if (text.trim().isNotEmpty) {
            lines.add(_LyricLine(text, start, end));
          }
        }
      }

      // 2) If empty, try to find a better match by searching using title + artist
      List<_LyricLine> resolved = lines;
      if (resolved.isEmpty) {
        final track = _audioService.currentTrack;
        final queryTitle = (track != null && track.title.trim().isNotEmpty)
            ? track.title
            : widget.title;
        final queryArtist = (track != null && track.artist.trim().isNotEmpty)
            ? track.artist
            : widget.artist;
        final searchQuery = ('$queryTitle $queryArtist').trim();

        if (searchQuery.isNotEmpty) {
          try {
            final searchResults = await _ytmusic.searchSongs(searchQuery);
            if (searchResults.isNotEmpty) {
              // Try a few candidates to find one with timed lyrics
              for (var i = 0; i < searchResults.length && i < 5; i++) {
                final altVid = searchResults[i].videoId;
                if (altVid.isNotEmpty && altVid != vid) {
                  final altLyrics = await _ytmusic.getTimedLyrics(altVid);
                  if (altLyrics != null &&
                      altLyrics.timedLyricsData.isNotEmpty) {
                    final altLines = <_LyricLine>[];
                    for (final l in altLyrics.timedLyricsData) {
                      final text = (l.lyricLine ?? '').toString();
                      final start = l.cueRange?.startTimeMilliseconds ?? 0;
                      final end =
                          l.cueRange?.endTimeMilliseconds ?? (start + 2000);
                      if (text.trim().isNotEmpty) {
                        altLines.add(_LyricLine(text, start, end));
                      }
                    }
                    resolved = altLines;
                    _lyricsSource = altLyrics.sourceMessage;
                    break;
                  }
                }
              }
            }
          } catch (_) {
            // Ignore search failures
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _lyrics = resolved;
        _lyricsForVideoId = vid;
        if (resolved.isEmpty) {
          _lyricsError = 'Lyrics not available';
        } else {
          // Cache for future toggles
          _lyricsCache[vid] = resolved;
        }
        // Reset active index so the next frame can auto-center the first active line
        _activeLyricIndex = -1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lyricsError = 'Failed to load lyrics';
      });
    } finally {
      if (mounted) {
        setState(() => _lyricsLoading = false);
      }
    }
  }

  Widget _buildLyricsOverlay(TrackInfo? info) {
    final positionMs = (info?.position ?? Duration.zero).inMilliseconds;

    // Schedule auto-scroll to the active line after build
    if (_showLyrics && !_lyricsLoading && _lyrics.isNotEmpty) {
      final newIndex = _findActiveLyricIndex(positionMs);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeAutoScrollToLyric(newIndex);
      });
    }

    return Container(
      color: Colors.black.withOpacity(0.55),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lyrics',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (_lyricsSource != null && _lyricsSource!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            _lyricsSource!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _showLyrics = false),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _lyricsLoading
                    ? Center(
                        child: LoadingIndicatorM3E(
                          containerColor: bgcolor.withAlpha(100),
                          color: appbarcolor.withAlpha(155),
                          polygons: [
                            MaterialShapes.sunny,
                            MaterialShapes.cookie9Sided,
                            MaterialShapes.pill,
                            MaterialShapes.arrow,
                            MaterialShapes.cookie7Sided,
                            MaterialShapes.boom,
                          ],
                        ),
                      )
                    : (_lyricsError != null
                          ? Center(
                              child: Text(
                                _lyricsError!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n is UserScrollNotification) {
                                  _userScrollingLyrics =
                                      n.direction != ScrollDirection.idle;
                                } else if (n is ScrollEndNotification) {
                                  _userScrollingLyrics = false;
                                }
                                return false;
                              },
                              child: ListView.builder(
                                controller: _lyricsScrollController,
                                itemCount: _lyrics.length,
                                itemBuilder: (context, i) {
                                  final line = _lyrics[i];
                                  final active = line.isActive(positionMs);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4.0,
                                    ),
                                    child: Text(
                                      line.text,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: active
                                            ? Colors.white
                                            : Colors.white70,
                                        fontSize: active ? 18 : 14,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _findActiveLyricIndex(int positionMs) {
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].isActive(positionMs)) return i;
    }
    // If none active, find the last line before current position
    for (int i = _lyrics.length - 1; i >= 0; i--) {
      if (positionMs >= _lyrics[i].startMs) return i;
    }
    return 0;
  }

  void _maybeAutoScrollToLyric(int index) {
    if (index < 0 || index >= _lyrics.length) return;
    if (!_lyricsScrollController.hasClients) return;
    if (_userScrollingLyrics) return; // don't fight the user

    // Throttle animations
    final now = DateTime.now();
    if (now.difference(_lastAutoScrollAt).inMilliseconds < 350) return;

    if (_activeLyricIndex == index) return;
    _activeLyricIndex = index;

    final pos = _lyricsScrollController.position;
    final viewport = pos.viewportDimension;
    final target =
        (index * _lyricRowApproxHeight) -
        (viewport / 2 - _lyricRowApproxHeight / 2);
    final clamped = target.clamp(0.0, pos.maxScrollExtent);

    // If we're already close to target, skip to avoid jitter
    if ((pos.pixels - clamped).abs() < 8) return;

    _lastAutoScrollAt = now;
    _lyricsScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }
}

class _LyricLine {
  final String text;
  final int startMs;
  final int endMs;
  _LyricLine(this.text, this.startMs, this.endMs);
  bool isActive(int positionMs) => positionMs >= startMs && positionMs < endMs;
}
