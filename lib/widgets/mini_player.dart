import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/track_info.dart';
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

  @override
  Widget build(BuildContext context) {
    final audioService = AudioPlayerService();

    return ValueListenableBuilder<bool>(
      valueListenable: audioService.isPreparing,
      builder: (context, preparing, _) {
        return StreamBuilder<TrackInfo>(
          stream: audioService.trackInfoStream,
          builder: (context, trackInfoSnapshot) {
            final trackInfo = trackInfoSnapshot.data;
            final hasTrack = trackInfo?.track != null;

            // Consider metadata available when we have duration or artwork (or both)
            final bool metadataReady =
                hasTrack &&
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
              child: Container(
                height: 80,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgcolor, // Use player background color
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Progress bar - now uses the synchronized progress from trackInfo
                    Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: iconcolor.withAlpha(50),
                        valueColor: AlwaysStoppedAnimation<Color>(appbarcolor),
                      ),
                    ),

                    // Main content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            // Album art with caching
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: cardcolor,
                              ),
                              child: currentTrack.thumbnailUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: currentTrack.thumbnailUrl!,
                                      borderRadius: BorderRadius.circular(8),
                                      fit: BoxFit.cover,
                                      width: 48,
                                      height: 48,
                                      errorWidget: Icon(
                                        Icons.music_note,
                                        color: iconcolor.withAlpha(180),
                                        size: 24,
                                      ),
                                    )
                                  : Icon(
                                      Icons.music_note,
                                      color: iconcolor.withAlpha(180),
                                      size: 24,
                                    ),
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
                                      color: txtcolor,
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
                                      color: txtcolor.withAlpha(180),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // Previous button
                            IconButton(
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

                            // Play/Pause button with loading state
                            StreamBuilder<PlayerState>(
                              stream: audioService.playerStateStream,
                              builder: (context, snapshot) {
                                final state = snapshot.data;
                                final isLoading =
                                    state?.processingState ==
                                        ProcessingState.loading ||
                                    state?.processingState ==
                                        ProcessingState.buffering;
                                final isPlaying =
                                    trackInfoSnapshot.data?.isPlaying ?? false;

                                if (isLoading) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              txtcolor,
                                            ),
                                      ),
                                    ),
                                  );
                                }

                                return IconButton(
                                  onPressed: () async {
                                    if (isPlaying) {
                                      await audioService.pause();
                                    } else {
                                      await audioService.play();
                                    }
                                  },
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: txtcolor,
                                    size: 28,
                                  ),
                                );
                              },
                            ),

                            // Next button
                            IconButton(
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkeletonMiniPlayer() {
    return Container(
      height: 80,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgcolor,
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
          baseColor: cardcolor,
          highlightColor: cardcolor.withAlpha(160),
          duration: const Duration(milliseconds: 900),
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
                  color: cardcolor,
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
                        color: cardcolor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(180),
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
                  color: cardcolor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cardcolor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: cardcolor,
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
