import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';
import 'package:sautifyv2/blocs/audio_player_cubit.dart';
import 'package:sautifyv2/blocs/download/download_cubit.dart';
import 'package:sautifyv2/blocs/download/download_state.dart';
import 'package:sautifyv2/blocs/library/library_cubit.dart';
import 'package:sautifyv2/blocs/library/library_state.dart';
import 'package:sautifyv2/blocs/player/player_cubit.dart';
import 'package:sautifyv2/blocs/player/player_state.dart';
import 'package:sautifyv2/blocs/theme/theme_cubit.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/screens/current_playlist_screen.dart';
import 'package:sautifyv2/screens/equalizer_screen.dart';
import 'package:sautifyv2/widgets/local_artwork_image.dart';
import 'package:sautifyv2/widgets/playlist_loading_progress.dart';
import 'package:squiggly_slider/slider.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final String artist;
  final String? imageUrl;
  final Duration? duration;
  final String? videoId;
  final List<StreamingData>? playlist;
  final int? initialIndex;
  final String? sourceType;
  final String? sourceName;

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
  bool _started = false;

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndsAt;

  @override
  void initState() {
    super.initState();
    _startPlaybackOnce();
  }

  @override
  void dispose() {
    try {
      _sleepTimer?.cancel();
    } catch (_) {}
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    super.dispose();
  }

  void _cancelSleepTimer({bool showToast = true}) {
    try {
      _sleepTimer?.cancel();
    } catch (_) {}
    _sleepTimer = null;
    _sleepTimerEndsAt = null;

    if (showToast && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sleep timer off'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _setSleepTimer(Duration duration) {
    _cancelSleepTimer(showToast: false);

    _sleepTimerEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      if (!mounted) return;
      final audio = context.read<AudioPlayerCubit>();
      if (audio.state.isPlaying) {
        audio.service.pause();
      }
      _cancelSleepTimer(showToast: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sleep timer ended'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    if (mounted) {
      final mins = duration.inMinutes;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sleep timer: $mins min'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showSleepTimerSheet() async {
    if (!mounted) return;

    final selection = await showModalBottomSheet<Duration?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final endsAt = _sleepTimerEndsAt;
        final remaining =
            endsAt != null ? endsAt.difference(DateTime.now()) : Duration.zero;

        Widget remainingWidget = const SizedBox.shrink();
        if (endsAt != null && remaining.inSeconds > 0) {
          remainingWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Ends in ${remaining.inMinutes} min',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          );
        }

        Widget tile(String label, Duration? value) {
          return ListTile(
            title: Text(label),
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sleep timer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              remainingWidget,
              tile('Off', null),
              tile('5 minutes', const Duration(minutes: 5)),
              tile('10 minutes', const Duration(minutes: 10)),
              tile('15 minutes', const Duration(minutes: 15)),
              tile('30 minutes', const Duration(minutes: 30)),
              tile('60 minutes', const Duration(minutes: 60)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selection == null) {
      _cancelSleepTimer();
    } else {
      _setSleepTimer(selection);
    }
  }

  Future<void> _showMoreMenu() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(
            {required IconData icon,
            required String label,
            required String value}) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                  icon: Icons.restore,
                  label: 'Resume last session',
                  value: 'resume'),
              item(
                  icon: Icons.timer_outlined,
                  label: 'Sleep timer',
                  value: 'sleep'),
              item(
                  icon: Icons.playlist_play,
                  label: 'Current queue',
                  value: 'queue'),
              item(icon: Icons.equalizer, label: 'Equalizer', value: 'eq'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'resume') {
      final ok = await context
          .read<AudioPlayerCubit>()
          .service
          .restoreLastSession(autoPlay: true);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing to resume yet'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (action == 'sleep') {
      await _showSleepTimerSheet();
      return;
    }
    if (action == 'queue') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CurrentPlaylistScreen(),
        ),
      );
      return;
    }
    if (action == 'eq') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const EqualizerScreen(),
        ),
      );
    }
  }

  void _startPlaybackOnce() {
    if (_started) return;
    if (widget.videoId == null && widget.playlist == null) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = context.read<AudioPlayerCubit>();
      if (widget.playlist != null) {
        audio.playPlaylist(
          widget.playlist!,
          index: widget.initialIndex ?? 0,
          sourceType: widget.sourceType,
          sourceName: widget.sourceName,
        );
        return;
      }

      final id = widget.videoId;
      if (id != null) {
        audio.playTrack(
          StreamingData(
            videoId: id,
            title: widget.title,
            artist: widget.artist,
            thumbnailUrl: widget.imageUrl,
            duration: widget.duration,
          ),
          sourceType: widget.sourceType,
          sourceName: widget.sourceName,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AudioPlayerCubit, AudioPlayerState>(
          listenWhen: (previous, current) =>
              previous.currentTrack?.videoId != current.currentTrack?.videoId,
          listener: (context, state) {
            final track = state.currentTrack;
            if (track != null) {
              // Update colors
              if (track.isLocal && track.localId != null) {
                context.read<ThemeCubit>().getColorFromLocalId(track.localId!);
              } else if (track.thumbnailUrl != null &&
                  !_looksLikeFilePath(track.thumbnailUrl!)) {
                context.read<ThemeCubit>().getColor(track.thumbnailUrl!);
              }

              // Fetch lyrics if they were shown
              if (context.read<PlayerCubit>().state.showLyrics) {
                context.read<PlayerCubit>().fetchLyrics(
                      track.videoId,
                      track.title,
                      track.artist,
                    );
              }
            }
          },
        ),
        BlocListener<DownloadCubit, DownloadState>(
          listenWhen: (previous, current) =>
              (previous.eventId ?? 0) != (current.eventId ?? 0),
          listener: (context, state) {
            final msg = state.eventMessage;
            if (msg == null || msg.trim().isEmpty) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ],
      child: BlocBuilder<PlayerCubit, PlayerState>(
        builder: (context, playerState) {
          return BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
            builder: (context, audioState) {
              final track = audioState.currentTrack;
              final currentTitle = track?.title ?? widget.title;
              final currentArtist = track?.artist ?? widget.artist;
              final artworkUrl = track?.thumbnailUrl ?? widget.imageUrl;
              final isLocal = track?.isLocal ?? false;

              return Scaffold(
                body: Stack(
                  children: [
                    // Background Gradient
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: playerState.bgColors,
                        ),
                      ),
                    ),

                    // Blurred Background Artwork
                    if (artworkUrl != null || isLocal)
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Stack(
                            key: ValueKey(track?.videoId ?? widget.videoId),
                            fit: StackFit.expand,
                            children: [
                              if (isLocal && track?.localId != null)
                                LocalArtworkImage(
                                  localId: track!.localId!,
                                  type: ArtworkType.AUDIO,
                                  fit: BoxFit.cover,
                                  placeholder: Container(color: Colors.black),
                                )
                              else if (artworkUrl != null &&
                                  _looksLikeFilePath(artworkUrl))
                                Image.file(
                                  File(_stripFileScheme(artworkUrl)),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              else if (artworkUrl != null)
                                CachedNetworkImage(
                                  imageUrl: artworkUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(color: Colors.black),
                                ),
                              BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                child: Container(
                                  color: Colors.black.withAlpha(100),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Main Content
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          children: [
                            _buildTopBar(context, audioState),
                            const Spacer(),
                            _buildAlbumArt(context, track, playerState),
                            const Spacer(),
                            _buildSongInfo(context, track, currentTitle,
                                currentArtist, audioState),
                            const SizedBox(height: 30),
                            _buildProgressBar(context, audioState),
                            const SizedBox(height: 40),
                            _buildControlButtons(context, audioState),
                            const SizedBox(height: 30),
                            _buildBottomControls(context, playerState, track),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    // Loading Progress
                    const Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: PlaylistLoadingProgress(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _looksLikeFilePath(String value) {
    return value.startsWith('file://') ||
        value.startsWith('/') ||
        value.contains('\\');
  }

  String _stripFileScheme(String value) {
    return value.startsWith('file://')
        ? value.replaceFirst('file://', '')
        : value;
  }

  Widget _buildTopBar(BuildContext context, AudioPlayerState state) {
    final type = (state.sourceType ?? "QUEUE").toUpperCase();
    final name = state.sourceName ?? "";

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  "PLAYING FROM $type",
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withAlpha(150),
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showMoreMenu();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(
      BuildContext context, StreamingData? track, PlayerState playerState) {
    return Expanded(
      flex: 5,
      child: Stack(
        children: [
          Center(
            child: Hero(
              tag: "album_art_${track?.videoId ?? "default"}",
              child: Container(
                width: MediaQuery.of(context).size.width * 0.92,
                height: MediaQuery.of(context).size.width * 0.92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (track?.isLocal == true && track?.localId != null)
                      ? LocalArtworkImage(
                          localId: track!.localId!,
                          type: ArtworkType.AUDIO,
                          fit: BoxFit.cover,
                          placeholder: _buildDefaultAlbumArt(context),
                        )
                      : (track?.thumbnailUrl != null &&
                              _looksLikeFilePath(track!.thumbnailUrl!))
                          ? Image.file(
                              File(_stripFileScheme(track.thumbnailUrl!)),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : track?.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: track!.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      _buildDefaultAlbumArt(context),
                                  errorWidget: (context, url, error) =>
                                      _buildDefaultAlbumArt(context),
                                )
                              : _buildDefaultAlbumArt(context),
                ),
              ),
            ),
          ),
          if (playerState.showLyrics)
            Positioned.fill(
              child: _buildLyricsOverlay(context, playerState, track),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultAlbumArt(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      child: const Center(
        child: Icon(Icons.music_note, size: 80),
      ),
    );
  }

  Widget _buildLyricsOverlay(
      BuildContext context, PlayerState state, StreamingData? track) {
    if (state.lyricsLoading) {
      return Center(
          child: CircularProgressIndicatorM3E(
        activeColor: Theme.of(context).colorScheme.primary,
        trackColor: Theme.of(context).colorScheme.primary.withAlpha(180),
      ));
    }

    if (state.lyricsError != null) {
      return Center(child: Text(state.lyricsError!));
    }

    if (state.lyrics.isEmpty) {
      return const Center(child: Text("No lyrics found"));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        itemCount: state.lyrics.length,
        itemBuilder: (context, index) {
          final line = state.lyrics[index];
          final isActive = index == state.activeLyricIndex;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isActive ? 22 : 18,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : Colors.white.withAlpha(150),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, StreamingData? track,
      String title, String artist, AudioPlayerState audioState) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, libraryState) {
        final isLiked = track != null &&
            libraryState.favorites.any((s) => s.videoId == track.videoId);

        final current = audioState.currentTrack ?? track;
        final isOffline =
            (audioState.sourceType ?? '').toUpperCase() == 'OFFLINE';
        final isLocalTrack = (current?.isLocal ?? false) ||
            ((current?.videoId ?? '').startsWith('local_')) ||
            ((current?.videoId ?? '').startsWith('local:'));
        final disableDownload = isOffline || isLocalTrack;

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 35,
                    child: title.length > 20
                        ? Marquee(
                            text: title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            blankSpace: 50,
                            velocity: 30,
                            pauseAfterRound: const Duration(seconds: 2),
                          )
                        : Text(
                            title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withAlpha(180),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded, size: 28),
              onPressed: disableDownload
                  ? null
                  : () {
                      final currentTrack =
                          context.read<AudioPlayerCubit>().state.currentTrack;

                      if (currentTrack == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No track playing yet'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      final downloadCubit = context.read<DownloadCubit>();
                      if (!downloadCubit.state.isInitialized) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Downloads are not ready yet'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      if (downloadCubit.state.downloadingIds
                          .contains(currentTrack.videoId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Already downloading'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      if (downloadCubit.isDownloaded(currentTrack.videoId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Already downloaded'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _DownloadProgressDialog(
                          videoId: currentTrack.videoId,
                          title: currentTrack.title,
                        ),
                      );

                      downloadCubit.downloadTrack(currentTrack);
                    },
            ),
            IconButton(
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                color: isLiked ? Colors.red : null,
                size: 28,
              ),
              onPressed: () {
                if (track != null) {
                  context.read<LibraryCubit>().toggleFavorite(track);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgressBar(BuildContext context, AudioPlayerState state) {
    final total = state.duration;
    final position = state.position;
    final buffered = state.bufferedPosition;

    final posRatio = total.inMilliseconds > 0
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bufRatio = total.inMilliseconds > 0
        ? (buffered.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Buffered Progress
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 1.5,
              ),
              child: SquigglySlider(
                value: bufRatio,
                onChanged: null,
                activeColor:
                    Theme.of(context).colorScheme.primary.withAlpha(50),
                inactiveColor: Colors.transparent,
                squiggleAmplitude: 0,
                squiggleWavelength: 0,
                squiggleSpeed: 0,
              ),
            ),
            // Current Position
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 3.0,
              ),
              child: SquigglySlider(
                value: posRatio,
                onChanged: (value) {
                  final newPos = Duration(
                      milliseconds: (value * total.inMilliseconds).round());
                  context.read<AudioPlayerCubit>().seek(newPos);
                },
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor:
                    Theme.of(context).colorScheme.primary.withAlpha(30),
                squiggleAmplitude: 1.5,
                squiggleWavelength: 4.0,
                squiggleSpeed: 0.05,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(position)),
            Text(_formatDuration(total)),
          ],
        ),
      ],
    );
  }

  Widget _buildControlButtons(BuildContext context, AudioPlayerState state) {
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final loopMode = state.loopMode;
    final isShuffle = state.isShuffleEnabled;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: isShuffle ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: () => context.read<AudioPlayerCubit>().toggleShuffle(),
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 36),
          onPressed: () => context.read<AudioPlayerCubit>().previous(),
        ),
        GestureDetector(
          onTap: () => context.read<AudioPlayerCubit>().togglePlayPause(),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isBuffering
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: LoadingIndicatorM3E(
                        variant: LoadingIndicatorM3EVariant.contained,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 48,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 36),
          onPressed: () => context.read<AudioPlayerCubit>().next(),
        ),
        IconButton(
          icon: Icon(
            loopMode == ja.LoopMode.one ? Icons.repeat_one : Icons.repeat,
            color: loopMode != ja.LoopMode.off
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          onPressed: () => context.read<AudioPlayerCubit>().toggleRepeat(),
        ),
      ],
    );
  }

  Widget _buildBottomControls(
      BuildContext context, PlayerState playerState, StreamingData? track) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            playerState.showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
            color: playerState.showLyrics
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          onPressed: () {
            context.read<PlayerCubit>().toggleLyrics();
            if (!playerState.showLyrics && track != null) {
              context.read<PlayerCubit>().fetchLyrics(
                    track.videoId,
                    track.title,
                    track.artist,
                  );
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.playlist_play),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CurrentPlaylistScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.equalizer),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EqualizerScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.timer_outlined),
          onPressed: () {
            _showSleepTimerSheet();
          },
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}

class _DownloadProgressDialog extends StatelessWidget {
  final String videoId;
  final String title;

  const _DownloadProgressDialog({
    required this.videoId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<DownloadCubit, DownloadState>(
      listenWhen: (previous, current) =>
          (previous.eventId ?? 0) != (current.eventId ?? 0),
      listener: (context, state) {
        if (state.eventVideoId != videoId) return;
        final done = state.eventMessage == 'Downloaded';
        if (done || state.eventIsError) {
          Navigator.of(context).pop();
        }
      },
      child: WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Downloading'),
          content: BlocBuilder<DownloadCubit, DownloadState>(
            buildWhen: (previous, current) =>
                previous.progressReceived != current.progressReceived ||
                previous.progressTotal != current.progressTotal ||
                previous.activeDownloadVideoId != current.activeDownloadVideoId,
            builder: (context, state) {
              final isActive = state.activeDownloadVideoId == videoId;
              final ratio = isActive ? state.progressRatio : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicatorM3E(
                    value: ratio,
                    shape: ProgressM3EShape.wavy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ratio == null
                        ? 'Starting…'
                        : '${(ratio * 100).toStringAsFixed(0)}%',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
