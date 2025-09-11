import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_audio_output/flutter_audio_output.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/screens/current_playlist_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

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
  @override
  void initState() {
    super.initState();
    _audioService = AudioPlayerService(); // This gets the singleton instance

    // Only load playlist if provided and audio service doesn't have a playlist
    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      _loadPlaylist();
    } else if (widget.videoId != null && _audioService.playlist.isEmpty) {
      _loadSingleTrack();
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
      await _audioService.loadPlaylist(
        widget.playlist!,
        initialIndex: widget.initialIndex ?? 0,
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
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgcolor.withAlpha(200), bgcolor, Colors.black],
                ),
              ),
            ),

            // Background image + blur using CachedNetworkImage (memory friendly)
            if (widget.imageUrl != null)
              Positioned.fill(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: Container(color: Colors.black),
                    ),
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                      child: Container(color: Colors.black.withAlpha(100)),
                    ),
                  ],
                ),
              ),

            // Main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: StreamBuilder<TrackInfo>(
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

                    return Column(
                      children: [
                        // Top bar
                        _buildTopBar(info),

                        const SizedBox(height: 40),

                        // Album art (repaint boundary to reduce repaints)
                        Expanded(
                          flex: 3,
                          child: RepaintBoundary(
                            child: _buildAlbumArt(artworkUrl),
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
                        _buildBottomControls(),

                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
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
        Column(
          children: [
            Text(
              typeLabel,
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
                style: TextStyle(
                  color: txtcolor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
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
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  borderRadius: BorderRadius.circular(12),
                  fit: BoxFit.cover,
                  width: 320,
                  height: 320,
                  errorWidget: _buildDefaultAlbumArt(),
                )
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
              Text(
                title,
                style: TextStyle(
                  color: txtcolor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
            isLiked ? Icons.favorite : Icons.favorite_border,
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
        Container(
          decoration: BoxDecoration(color: txtcolor, shape: BoxShape.circle),
          child: StreamBuilder<PlayerState>(
            stream: _audioService.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;
              final isPlaying =
                  info?.isPlaying ?? playerState?.playing ?? false;
              final processing = playerState?.processingState;
              final isLoading =
                  processing == ProcessingState.loading ||
                  processing == ProcessingState.buffering;

              return IconButton(
                onPressed: isLoading ? null : _togglePlayPause,
                icon: isLoading
                    ? SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(bgcolor),
                          ),
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: bgcolor,
                        size: 32,
                      ),
              );
            },
          ),
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

  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        /* IconButton(
          onPressed: () {},
          icon: Icon(Icons.devices, color: iconcolor.withAlpha(180), size: 24),
        ),*/
        Row(
          children: [
            Icon(Icons.headphones, color: appbarcolor, size: 16),
            const SizedBox(width: 8),
            Text(
              '${_currentOutput?.name ?? 'Unknown'} Playing...',
              style: TextStyle(
                color: appbarcolor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
}
