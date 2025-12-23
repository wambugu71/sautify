import 'dart:io';

/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:flutter/material.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/providers/set_dynamic_colors.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:skeletonizer/skeletonizer.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _initialReady = false; // becomes true when first track metadata is ready
  String? _lastProcessedUrl;
  int? _lastProcessedId;

  // Cache for artwork widget to prevent flickering
  Widget? _cachedArtwork;
  String? _cachedArtworkUrlKey;
  int? _cachedArtworkIdKey;

  @override
  Widget build(BuildContext context) {
    final audioService = AudioPlayerService();

    return ValueListenableBuilder<bool>(
      valueListenable: audioService.isPreparing,
      builder: (context, preparing, _) {
        return StreamBuilder<TrackInfo>(
          stream: audioService.trackInfo$,
          builder: (context, trackInfoSnapshot) {
            final trackInfo = trackInfoSnapshot.data;
            final hasTrack = trackInfo?.track != null;

            // Consider metadata available when we have duration or artwork (or both)
            final bool metadataReady = hasTrack &&
                ((trackInfo?.duration != null) ||
                    ((trackInfo?.track?.thumbnailUrl ?? '').isNotEmpty) ||
                    ((trackInfo?.title ?? '').isNotEmpty &&
                        (trackInfo?.artist ?? '').isNotEmpty));

            // Mark initial readiness once first metadata is available,
            // or when preparation ends while a track exists (safety fallback)
            if (!_initialReady && (metadataReady || (hasTrack && !preparing))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _initialReady = true);
              });
            }

            // Show skeleton only during the first load while preparing
            if (!_initialReady && preparing) {
              return _buildSkeletonMiniPlayer();
            }

            // Hide if nothing to show
            if (!hasTrack) {
              return const SizedBox.shrink();
            }

            final currentTrack = trackInfo!.track!;
            final progress = trackInfo.progress;

            // Logic to update colors
            bool shouldUpdateColors = false;
            if (currentTrack.isLocal && currentTrack.localId != null) {
              if (currentTrack.localId != _lastProcessedId) {
                shouldUpdateColors = true;
                _lastProcessedId = currentTrack.localId;
                _lastProcessedUrl = null;
              }
            } else if (currentTrack.thumbnailUrl != _lastProcessedUrl) {
              shouldUpdateColors = true;
              _lastProcessedUrl = currentTrack.thumbnailUrl;
              _lastProcessedId = null;
            }

            if (shouldUpdateColors) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  if (currentTrack.isLocal && currentTrack.localId != null) {
                    context.read<SetColors>().getColorFromLocalId(
                          currentTrack.localId!,
                        );
                  } else if (currentTrack.thumbnailUrl != null &&
                      currentTrack.thumbnailUrl!.isNotEmpty) {
                    context.read<SetColors>().getColor(
                          currentTrack.thumbnailUrl!,
                        );
                  } else {
                    context.read<SetColors>().setColors([
                      Theme.of(context).colorScheme.surface.withAlpha(200),
                      Theme.of(context).colorScheme.surface,
                      Colors.black,
                    ]);
                  }
                }
              });
            }

            final pryColors = context.watch<SetColors>().getPrimaryColors;

            // Update cached artwork if track changed
            if (_cachedArtwork == null ||
                _cachedArtworkIdKey != currentTrack.localId ||
                _cachedArtworkUrlKey != currentTrack.thumbnailUrl) {
              _cachedArtwork = _buildAlbumArt(currentTrack);
              _cachedArtworkIdKey = currentTrack.localId;
              _cachedArtworkUrlKey = currentTrack.thumbnailUrl;
            }

            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PlayerScreen(
                      title: currentTrack.title,
                      artist: currentTrack.artist,
                      imageUrl: currentTrack.thumbnailUrl,
                      // Don't pass playlist or initialIndex - just show current state
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
                      colors: pryColors.isNotEmpty
                          ? pryColors
                          : [
                              Theme.of(
                                context,
                              ).colorScheme.surface.withAlpha(200),
                              Theme.of(
                                context,
                              ).colorScheme.surface.withAlpha(150),
                            ],
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      //  tileMode: TileMode.mirror,
                    ),
                    //  color: appbarcolor.withAlpha(
                    //    10,
                    // ), // Use player background color
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withAlpha(100),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      //(value: 0.6),
                      // Progress bar - now uses the synchronized progress from trackInfo
                      Container(
                        height: 2.5,
                        margin: const EdgeInsets.only(left: 16, right: 16),
                        child: /* LinearProgressIndicatorM3E(
                          inset: 0,
                          shape: ProgressM3EShape.flat,
                          size: LinearProgressM3ESize.s,
                          value: progress,
                          trackColor: iconcolor,
                          activeColor: appbarcolor,
                        ),
                        */
                            Padding(
                          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12.0),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Theme.of(
                                context,
                              ).iconTheme.color?.withAlpha(100),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Main content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              // Album art with caching
                              M3Container.c7SidedCookie(
                                width: 48,
                                height: 48,
                                child: _cachedArtwork ??
                                    _buildAlbumArt(currentTrack),
                              ),

                              const SizedBox(width: 12),

                              // Song info
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentTrack.title,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
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

                              // Previous button
                              /*        Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100),
                                  color: appbarcolor.withAlpha(155),
                                ),
                                child: IconButton(
                                  onPressed: () async {
                                    await audioService.skipToPrevious();
                                  },
                                  icon: Icon(
                                    Icons.skip_previous,
                                    color: txtcolor,
                                    size: 24,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                ),*/

                              //repositioned  next  button only
                              IconButton(
                                onPressed: () async {
                                  await audioService.skipToNext();
                                },
                                icon: Icon(
                                  Icons.skip_next,
                                  color: Theme.of(context).iconTheme.color,
                                  size: 28,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 8),
                              // Play/Pause button with loading state (only when NOT playing AND preparing/loading)
                              ValueListenableBuilder<bool>(
                                valueListenable: audioService.isPreparing,
                                builder: (context, preparing, _) {
                                  return StreamBuilder<PlayerState>(
                                    stream: audioService.playerStateStream,
                                    builder: (context, snapshot) {
                                      final state = snapshot.data;
                                      final effectivePlaying = state?.playing ??
                                          (trackInfoSnapshot.data?.isPlaying ??
                                              false);
                                      final engineLoading =
                                          state?.processingState ==
                                                  ProcessingState.loading ||
                                              state?.processingState ==
                                                  ProcessingState.buffering;
                                      final isLoading = (!effectivePlaying) &&
                                          (preparing || engineLoading);

                                      if (isLoading) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0,
                                          ),
                                          child: SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: LoadingIndicatorM3E(
                                              containerColor: Theme.of(
                                                context,
                                              ).colorScheme.surface,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withAlpha(155),
                                            ),
                                          ),
                                        );
                                      }

                                      return IconButton(
                                        style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(32, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () async {
                                          if (effectivePlaying) {
                                            await audioService.pause();
                                          } else {
                                            await audioService.play();
                                          }
                                        },
                                        icon: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(
                                            effectivePlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                            size: 28,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),

                              // Next button
                              /*    Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100),
                                  color: appbarcolor.withAlpha(155),
                                ),
                                child: IconButton(
                                  onPressed: () async {
                                    await audioService.skipToNext();
                                  },
                                  icon: Icon(
                                    Icons.skip_next,
                                    color: txtcolor,
                                    size: 24,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),*/
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
        );
      },
    );
  }

  Widget _buildAlbumArt(dynamic currentTrack) {
    // Handle local files with OnAudioQuery
    if (currentTrack.isLocal && currentTrack.localId != null) {
      return QueryArtworkWidget(
        key: ValueKey('local_art_${currentTrack.localId}'),
        id: currentTrack.localId!,
        type: ArtworkType.AUDIO,
        artworkHeight: 48,
        artworkWidth: 48,
        artworkFit: BoxFit.cover,
        artworkBorder: BorderRadius.circular(8),
        nullArtworkWidget: Icon(
          Icons.music_note,
          color: Theme.of(context).iconTheme.color?.withAlpha(180),
          size: 24,
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

  Widget _buildSkeletonMiniPlayer() {
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
