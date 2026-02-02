/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = AudioPlayerService();

    return StreamBuilder<TrackInfo>(
      stream: audioService.trackInfoStream,
      builder: (context, trackInfoSnapshot) {
        final trackInfo = trackInfoSnapshot.data;

        // Don't show mini player if no track is loaded
        if (trackInfo?.track == null) {
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

                        // Play/Pause button with loading state (service preparing OR engine loading)
                        ValueListenableBuilder<bool>(
                          valueListenable: audioService.isPreparing,
                          builder: (context, preparing, _) {
                            return StreamBuilder<PlayerState>(
                              stream: audioService.playerStateStream,
                              builder: (context, snapshot) {
                                final state = snapshot.data;
                                final effectivePlaying =
                                    state?.playing ??
                                    (trackInfoSnapshot.data?.isPlaying ??
                                        false);
                                final engineLoading =
                                    state?.processingState ==
                                        ProcessingState.loading ||
                                    state?.processingState ==
                                        ProcessingState.buffering;
                                final isLoading =
                                    (!effectivePlaying) &&
                                    (preparing || engineLoading);

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
                                    if (effectivePlaying) {
                                      await audioService.pause();
                                    } else {
                                      await audioService.play();
                                    }
                                  },
                                  icon: Icon(
                                    effectivePlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: txtcolor,
                                    size: 28,
                                  ),
                                );
                              },
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
  }
}

