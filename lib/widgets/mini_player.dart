/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sautifyv2/blocs/audio_player_cubit.dart';
import 'package:sautifyv2/blocs/theme/theme_cubit.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/widgets/local_artwork_image.dart';
import 'package:skeletonizer/skeletonizer.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  StreamingData? _lastNonNullTrack;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AudioPlayerCubit, AudioPlayerState>(
      listenWhen: (prev, curr) {
        final prevKey = _trackKey(prev.currentTrack);
        final currKey = _trackKey(curr.currentTrack);
        return prevKey != currKey;
      },
      listener: (context, state) {
        final track = state.currentTrack;
        if (track == null) return;

        if (track.isLocal && track.localId != null) {
          context.read<ThemeCubit>().getColorFromLocalId(track.localId!);
          return;
        }

        final thumb = track.thumbnailUrl;
        if (thumb != null && thumb.isNotEmpty) {
          context.read<ThemeCubit>().getColor(thumb);
          return;
        }

        context.read<ThemeCubit>().setColors([
          Theme.of(context).colorScheme.surface.withAlpha(200),
          Theme.of(context).colorScheme.surface,
          Colors.black,
        ]);
      },
      child: BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
        builder: (context, state) {
          // First load skeleton: show only when preparing and no track yet
          if (state.isPreparing && state.currentTrack == null) {
            return _buildSkeletonMiniPlayer(context);
          }

          final currentTrack = state.currentTrack ?? _lastNonNullTrack;
          if (state.currentTrack != null) {
            _lastNonNullTrack = state.currentTrack;
          }
          if (currentTrack == null) {
            return const SizedBox.shrink();
          }

          final progress = state.duration.inMilliseconds <= 0
              ? 0.0
              : (state.position.inMilliseconds / state.duration.inMilliseconds)
                  .clamp(0.0, 1.0);

          final pryColors = context.select<ThemeCubit, List<Color>>(
            (cubit) => cubit.state.primaryColors,
          );

          final gradientColors = pryColors.isEmpty
              ? <Color>[]
              : (pryColors.length == 1
                  ? <Color>[pryColors[0], pryColors[0]]
                  : pryColors);

          final isLoading =
              (!state.isPlaying) && (state.isPreparing || state.isBuffering);

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                    title: currentTrack.title,
                    artist: currentTrack.artist,
                    imageUrl: currentTrack.thumbnailUrl,
                  ),
                ),
              );
            },
            child: Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(155),
              elevation: 11,
              child: Container(
                height: 60,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors.isNotEmpty
                        ? gradientColors
                        : [
                            Theme.of(context)
                                .colorScheme
                                .surface
                                .withAlpha(200),
                            Theme.of(context)
                                .colorScheme
                                .surface
                                .withAlpha(150),
                          ],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Theme.of(context).colorScheme.surface.withAlpha(100),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 2.5,
                      margin: const EdgeInsets.only(left: 16, right: 16),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withAlpha(100),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            M3Container.c7SidedCookie(
                              width: 48,
                              height: 48,
                              child: BlocSelector<AudioPlayerCubit,
                                  AudioPlayerState, StreamingData?>(
                                selector: (s) => s.currentTrack,
                                builder: (context, selected) {
                                  final t = selected ?? currentTrack;
                                  return RepaintBoundary(
                                    child: _buildAlbumArt(context, t),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentTrack.title,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentTrack.artist,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color
                                          ?.withAlpha(180),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  context.read<AudioPlayerCubit>().next(),
                              icon: Icon(
                                Icons.skip_next,
                                color: Theme.of(context).iconTheme.color,
                                size: 28,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                            if (isLoading)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: LoadingIndicatorM3E(
                                    containerColor:
                                        Theme.of(context).colorScheme.surface,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(155),
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => context
                                    .read<AudioPlayerCubit>()
                                    .togglePlayPause(),
                                icon: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    state.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                    size: 28,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String? _trackKey(dynamic track) {
    if (track == null) return null;
    if (track.isLocal && track.localId != null) return 'local:${track.localId}';
    final url = track.thumbnailUrl ?? '';
    if (url.isNotEmpty) return 'url:$url';
    return 'title:${track.title}:${track.artist}';
  }

  static Widget _buildAlbumArt(BuildContext context, dynamic currentTrack) {
    // Handle local files with OnAudioQuery
    if (currentTrack.isLocal && currentTrack.localId != null) {
      return ClipRRect(
        key: ValueKey('local_art_${currentTrack.localId}'),
        borderRadius: BorderRadius.circular(8),
        child: LocalArtworkImage(
          localId: currentTrack.localId!,
          type: ArtworkType.AUDIO,
          fit: BoxFit.cover,
          placeholder: Icon(
            Icons.music_note,
            color: Theme.of(context).iconTheme.color?.withAlpha(180),
            size: 24,
          ),
        ),
      );
    }

    // Handle local file paths
    if (currentTrack.thumbnailUrl != null &&
        (currentTrack.thumbnailUrl!.startsWith('file://') ||
            currentTrack.thumbnailUrl!.startsWith('/') ||
            currentTrack.thumbnailUrl!.contains('\\'))) {
      return ClipRRect(
        key: ValueKey('local_file_${currentTrack.thumbnailUrl}'),
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(currentTrack.thumbnailUrl!.replaceFirst('file://', '')),
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          gaplessPlayback: true,
          errorBuilder: (context, _, __) => Icon(
            Icons.music_note,
            color: Theme.of(context).iconTheme.color?.withAlpha(180),
            size: 24,
          ),
        ),
      );
    }

    // Handle remote URLs
    if (currentTrack.thumbnailUrl != null &&
        currentTrack.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        key: ValueKey('remote_art_${currentTrack.thumbnailUrl}'),
        placeholder: M3Container.c7SidedCookie(
          color: Theme.of(context).colorScheme.surface.withAlpha(155),
          child: LoadingIndicatorM3E(
            containerColor: Theme.of(
              context,
            ).colorScheme.surface.withAlpha(100),
            color: Theme.of(context).colorScheme.primary.withAlpha(155),
          ),
        ),
        imageUrl: currentTrack.thumbnailUrl!,
        borderRadius: BorderRadius.circular(8),
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorWidget: Icon(
          Icons.music_note,
          color: Theme.of(context).iconTheme.color?.withAlpha(180),
          size: 24,
        ),
      );
    }

    // Default fallback
    return Icon(
      Icons.music_note,
      color: Theme.of(context).iconTheme.color?.withAlpha(180),
      size: 24,
    );
  }

  static Widget _buildSkeletonMiniPlayer(BuildContext context) {
    return Container(
      height: 80,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Skeletonizer(
        enabled: true,
        effect: ShimmerEffect(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          baseColor: Theme.of(context).cardColor,
          highlightColor: Theme.of(context).cardColor.withAlpha(160),
          duration: const Duration(milliseconds: 980),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Artwork placeholder
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              // Title/artist placeholders
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor.withAlpha(180),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              // Controls placeholders
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
