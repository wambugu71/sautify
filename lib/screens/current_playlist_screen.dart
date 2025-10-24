/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:flutter/material.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

class CurrentPlaylistScreen extends StatelessWidget {
  final AudioPlayerService audioService;

  const CurrentPlaylistScreen({super.key, required this.audioService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgcolor,
      appBar: AppBar(
        backgroundColor: bgcolor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back, color: iconcolor),
        ),
        title: Text(
          'Now Playing',
          style: TextStyle(
            color: txtcolor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Rebuild count only when audioService notifies (playlist changes)
          AnimatedBuilder(
            animation: audioService,
            builder: (context, _) {
              final count = audioService.playlist.length;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '$count songs',
                    style: TextStyle(
                      color: txtcolor.withAlpha(180),
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: audioService,
        builder: (context, _) {
          final playlist = audioService.playlist;

          if (playlist.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 64,
                    color: iconcolor.withAlpha(100),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No songs in playlist',
                    style: TextStyle(
                      color: txtcolor.withAlpha(180),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          }

          // Use the service's playlist index (shuffle-aware mapping)
          final currentIndex = audioService.currentIndex;

          return SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  // border: Border.all(color: txtcolor.withAlpha(40), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    top: 4,
                    bottom: 8 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: playlist.length,
                  /*  separatorBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, color: txtcolor.withAlpha(40)),
                  ),*/
                  itemBuilder: (context, index) {
                    final track = playlist[index];
                    final isCurrentTrack = index == currentIndex;

                    return Container(
                      color: isCurrentTrack
                          ? appbarcolor.withAlpha(30)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          if (index != currentIndex) {
                            await audioService.seek(
                              Duration.zero,
                              index: index,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Artwork
                              M3Container.square(
                                /*   width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: cardcolor,
                                ),*/
                                child: track.thumbnailUrl != null
                                    ? CachedNetworkImage(
                                        placeholder: M3Container.square(
                                          color: bgcolor.withAlpha(155),
                                          child: LoadingIndicatorM3E(
                                            color: appbarcolor.withAlpha(155),
                                          ),
                                        ),
                                        imageUrl: track.thumbnailUrl!,
                                        borderRadius: BorderRadius.circular(10),
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

                              // Title + artist/duration
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      style: TextStyle(
                                        color: isCurrentTrack
                                            ? appbarcolor
                                            : txtcolor,
                                        fontSize: 15,
                                        fontWeight: isCurrentTrack
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            track.artist,
                                            style: TextStyle(
                                              color: isCurrentTrack
                                                  ? appbarcolor.withAlpha(180)
                                                  : txtcolor.withAlpha(180),
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (track.duration != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatDuration(track.duration!),
                                            style: TextStyle(
                                              color: txtcolor.withAlpha(120),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 12),

                              // Trailing: now-playing indicator + index
                              if (isCurrentTrack)
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: appbarcolor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    Icons.volume_up,
                                    color: appbarcolor,
                                    size: 16,
                                  ),
                                ),
                              if (isCurrentTrack) const SizedBox(width: 8),
                              Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isCurrentTrack
                                      ? appbarcolor
                                      : txtcolor.withAlpha(120),
                                  fontSize: 13,
                                  fontWeight: isCurrentTrack
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
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
