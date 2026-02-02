/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:cached_network_image/cached_network_image.dart' as cni;
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:sautifyv2/blocs/audio_player_cubit.dart';
import 'package:sautifyv2/blocs/library/library_cubit.dart';
import 'package:sautifyv2/blocs/library/library_state.dart';
import 'package:sautifyv2/blocs/playlist_overlay/playlist_overlay_cubit.dart';
import 'package:sautifyv2/blocs/playlist_overlay/playlist_overlay_state.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/widgets/playlist_loading_progress.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistOverlayScreen extends StatelessWidget {
  final Contents playlistContent;

  const PlaylistOverlayScreen({super.key, required this.playlistContent});

  @override
  Widget build(BuildContext context) {
    final playlistId = playlistContent.playlistId ?? '';
    return BlocProvider(
      create: (_) => PlaylistOverlayCubit(playlistId: playlistId)..init(),
      child: _PlaylistOverlayView(playlistContent: playlistContent),
    );
  }
}

class _PlaylistOverlayView extends StatelessWidget {
  final Contents playlistContent;
  const _PlaylistOverlayView({required this.playlistContent});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaylistOverlayCubit, PlaylistOverlayState>(
      builder: (context, overlayState) {
        return Scaffold(
          backgroundColor:
              Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
          body: SafeArea(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withOpacity(0.8),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    children: [
                      _buildHeader(context),
                      _buildPlaylistInfo(context, overlayState),
                      Expanded(child: _buildVideosList(context, overlayState)),
                    ],
                  ),
                ),
                const Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: PlaylistLoadingProgress(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).iconTheme.color,
              size: 32,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPlaylistInfo(
    BuildContext context,
    PlaylistOverlayState overlayState,
  ) {
    final playlistId = playlistContent.playlistId ?? '';
    final hasTracks = overlayState.videos.isNotEmpty;
    final isPreparing = context.select<AudioPlayerCubit, bool>(
      (cubit) => cubit.state.isPreparing,
    );
    final disabled = !hasTracks || overlayState.isBusy || isPreparing;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          M3Container.square(
            width: 150,
            height: 150,
            child: playlistContent.thumbnailUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: cni.CachedNetworkImage(
                      imageUrl: playlistContent.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Icon(
                        Icons.playlist_play,
                        size: 60,
                        color:
                            Theme.of(context).iconTheme.color?.withOpacity(0.6),
                      ),
                    ),
                  )
                : Icon(
                    Icons.playlist_play,
                    size: 60,
                    color: Theme.of(context).iconTheme.color?.withOpacity(0.6),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            playlistContent.name,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
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
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    child: Text(
                      playlistContent.artistName,
                      style: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withAlpha((255 * 0.7).toInt()),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      playlistContent.type.toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
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
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    BlocBuilder<LibraryCubit, LibraryState>(
                      builder: (context, libState) {
                        final isSaved = playlistId.isNotEmpty &&
                            libState.playlists.any((p) => p.id == playlistId);
                        return IconButton(
                          onPressed: (!hasTracks || playlistId.isEmpty)
                              ? null
                              : () async {
                                  final lib = context.read<LibraryCubit>();
                                  if (isSaved) {
                                    await lib.deletePlaylist(playlistId);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Removed from Library'),
                                      ),
                                    );
                                  } else {
                                    final tracksFull = overlayState.videos
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
                                        .toList(growable: false);
                                    final tracks = tracksFull.length > 25
                                        ? tracksFull.sublist(0, 25)
                                        : tracksFull;
                                    final saved = SavedPlaylist(
                                      id: playlistId,
                                      title: playlistContent.name,
                                      artworkUrl: playlistContent.thumbnailUrl,
                                      tracks: tracks,
                                    );
                                    await lib.savePlaylist(saved);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Saved to Library'),
                                      ),
                                    );
                                  }
                                },
                          icon: Icon(
                            isSaved ? Icons.favorite : Icons.favorite_border,
                            color: isSaved
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.download_for_offline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.shuffle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          final overlayCubit =
                              context.read<PlaylistOverlayCubit>();
                          overlayCubit.setBusy(true);
                          try {
                            final playlistFull = overlayState.videos
                                .map(
                                  (v) => StreamingData(
                                    videoId: v.id.value,
                                    title: v.title,
                                    artist: v.author,
                                    thumbnailUrl: v.thumbnails.highResUrl,
                                    duration: v.duration,
                                  ),
                                )
                                .toList(growable: false);
                            final playlist = playlistFull.length > 25
                                ? playlistFull.sublist(0, 25)
                                : playlistFull;
                            if (!context.mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => PlayerScreen(
                                  title: playlist.first.title,
                                  artist: playlist.first.artist,
                                  imageUrl: playlist.first.thumbnailUrl,
                                  duration: playlist.first.duration,
                                  playlist: playlist,
                                  initialIndex: 0,
                                  sourceType: 'PLAYLIST',
                                  sourceName: playlistContent.name,
                                ),
                              ),
                            );
                          } finally {
                            overlayCubit.setBusy(false);
                          }
                        },
                  icon: Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).iconTheme.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideosList(
    BuildContext context,
    PlaylistOverlayState overlayState,
  ) {
    if (overlayState.status == PlaylistOverlayStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Error loading playlist',
              style: TextStyle(color: Colors.red, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              overlayState.error ?? 'Unknown error',
              style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.color
                    ?.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  context.read<PlaylistOverlayCubit>().loadPlaylistVideos(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (overlayState.status == PlaylistOverlayStatus.loading) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, index) => _buildSkeletonVideoTile(context),
      );
    }

    if (overlayState.videos.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: overlayState.videos.length,
      itemBuilder: (context, i) => Builder(
        builder: (context) => _buildVideoTile(
          context: context,
          overlayState: overlayState,
          video: overlayState.videos[i],
          index: i,
          length: overlayState.videos.length,
        ),
      ),
    );
  }

  Widget _buildVideoTile({
    required BuildContext context,
    required PlaylistOverlayState overlayState,
    required Video video,
    required int index,
    required int length,
  }) {
    final trackNumber = index + 1;
    final track = StreamingData(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration,
    );

    final isPreparing = context.select<AudioPlayerCubit, bool>(
      (cubit) => cubit.state.isPreparing,
    );
    final disabled = overlayState.isBusy || isPreparing;
    final isStartingThis =
        overlayState.startingTrackId == track.videoId && overlayState.isBusy;

    return AbsorbPointer(
      absorbing: disabled,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(30),
          borderRadius: BorderRadius.vertical(
            top: index == 0
                ? const Radius.circular(33)
                : const Radius.circular(6),
            bottom: index == length - 1
                ? const Radius.circular(33)
                : const Radius.circular(6),
          ),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withAlpha(50),
            width: 1,
          ),
        ),
        child: isStartingThis
            ? SizedBox(
                height: 72,
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: ExpressiveLoadingIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        constraints: const BoxConstraints.tightFor(
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : GestureDetector(
                onTap: () async {
                  if (disabled) return;

                  final overlayCubit = context.read<PlaylistOverlayCubit>();
                  overlayCubit.beginStart(track.videoId);
                  try {
                    final playlistFull = overlayState.videos
                        .map(
                          (v) => StreamingData(
                            videoId: v.id.value,
                            title: v.title,
                            artist: v.author,
                            thumbnailUrl: v.thumbnails.highResUrl,
                            duration: v.duration,
                          ),
                        )
                        .toList(growable: false);

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

                    if (track.thumbnailUrl != null &&
                        track.thumbnailUrl!.isNotEmpty) {
                      try {
                        await ImageCacheService().preloadImage(
                          track.thumbnailUrl!,
                        );
                      } catch (_) {}
                    }

                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PlayerScreen(
                          title: track.title,
                          artist: track.artist,
                          imageUrl: track.thumbnailUrl,
                          duration: track.duration,
                          playlist: playlist,
                          initialIndex: cappedIndex,
                          sourceType: 'PLAYLIST',
                          sourceName: playlistContent.name,
                        ),
                      ),
                    );
                  } finally {
                    overlayCubit.endStart();
                  }
                },
                child: ListTile(
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: M3Container.c7SidedCookie(
                      width: 56,
                      height: 56,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: (track.thumbnailUrl != null &&
                                    track.thumbnailUrl!.isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: cni.CachedNetworkImage(
                                      imageUrl: track.thumbnailUrl!,
                                      placeholder: (context, url) =>
                                          M3Container.c7SidedCookie(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withAlpha(30),
                                        child: Center(
                                          child: ExpressiveLoadingIndicator(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withAlpha(155),
                                            constraints:
                                                const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(30),
                                      child: Icon(
                                        Icons.music_note,
                                        color: Theme.of(context)
                                            .iconTheme
                                            .color
                                            ?.withAlpha(155),
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
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    video.author,
                    style: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withAlpha(178),
                      fontSize: 12,
                    ),
                  ),
                  trailing: (video.duration != null)
                      ? Text(
                          _formatDuration(video.duration!),
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withAlpha((255 * 0.5).toInt()),
                            fontSize: 12,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
      ),
    );
  }

  Widget _buildSkeletonVideoTile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(50),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
        ),
        title: Container(
          height: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 10,
              width: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.play_arrow,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}

/*
                      Positioned.fill(
                        child: Column(
                          children: [
                            _buildHeader(context),
                            _buildPlaylistInfo(context, overlayState),
                            Expanded(child: _buildVideosList(context, overlayState)),
                          ],
                        ),
                      ),
                      const Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: PlaylistLoadingProgress(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        Widget _buildHeader(BuildContext context) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Theme.of(context).iconTheme.color,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          );
        }

        Widget _buildPlaylistInfo(
          BuildContext context,
          PlaylistOverlayState overlayState,
        ) {
          final playlistId = playlistContent.playlistId ?? '';
          final hasTracks = overlayState.videos.isNotEmpty;
          final isPreparing = context.select<AudioPlayerCubit, bool>(
            (cubit) => cubit.state.isPreparing,
          );
          final disabled = !hasTracks || overlayState.isBusy || isPreparing;

          return Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                M3Container.square(
                  width: 150,
                  height: 150,
                  child: playlistContent.thumbnailUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: playlistContent.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Icon(
                              Icons.playlist_play,
                              size: 60,
                              color: Theme.of(context)
                                  .iconTheme
                                  .color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.playlist_play,
                          size: 60,
                          color: Theme.of(context).iconTheme.color?.withOpacity(0.6),
                        ),
                ),
                const SizedBox(height: 16),
                Text(
                  playlistContent.name,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
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
                      children: [
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.4,
                          child: Text(
                            playlistContent.artistName,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withAlpha((255 * 0.7).toInt()),
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.primary.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            playlistContent.type.toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
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
                SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          BlocBuilder<LibraryCubit, LibraryState>(
                            builder: (context, libState) {
                              final isSaved = playlistId.isNotEmpty &&
                                  libState.playlists.any((p) => p.id == playlistId);
                              return IconButton(
                                onPressed: (!hasTracks || playlistId.isEmpty)
                                    ? null
                                    : () async {
                                        final lib = context.read<LibraryCubit>();
                                        if (isSaved) {
                                          await lib.deletePlaylist(playlistId);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Removed from Library'),
                                            ),
                                          );
                                        } else {
                                          final tracksFull = overlayState.videos
                                              .map(
                                                (v) => StreamingData(
                                                  videoId: v.id.value,
                                                  title: v.title,
                                                  artist: v.author,
                                                  thumbnailUrl: v.thumbnails.highResUrl,
                                                  duration: v.duration,
                                                ),
                                              )
                                              .toList(growable: false);
                                          final tracks = tracksFull.length > 25
                                              ? tracksFull.sublist(0, 25)
                                              : tracksFull;
                                          final saved = SavedPlaylist(
                                            id: playlistId,
                                            title: playlistContent.name,
                                            artworkUrl: playlistContent.thumbnailUrl,
                                            tracks: tracks,
                                          );
                                          await lib.savePlaylist(saved);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Saved to Library'),
                                            ),
                                          );
                                        }
                                      },
                                icon: Icon(
                                  isSaved ? Icons.favorite : Icons.favorite_border,
                                  color: isSaved
                                      ? Colors.red
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            onPressed: () {},
                            icon: Icon(
                              Icons.download_for_offline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: Icon(
                              Icons.shuffle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: disabled
                            ? null
                            : () async {
                                final overlayCubit =
                                    context.read<PlaylistOverlayCubit>();
                                overlayCubit.setBusy(true);
                                try {
                                  final playlistFull = overlayState.videos
                                      .map(
                                        (v) => StreamingData(
                                          videoId: v.id.value,
                                          title: v.title,
                                          artist: v.author,
                                          thumbnailUrl: v.thumbnails.highResUrl,
                                          duration: v.duration,
                                        ),
                                      )
                                      .toList(growable: false);
                                  final playlist = playlistFull.length > 25
                                      ? playlistFull.sublist(0, 25)
                                      : playlistFull;
                                  if (!context.mounted) return;
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => PlayerScreen(
                                        title: playlist.first.title,
                                        artist: playlist.first.artist,
                                        imageUrl: playlist.first.thumbnailUrl,
                                        duration: playlist.first.duration,
                                        playlist: playlist,
                                        initialIndex: 0,
                                        sourceType: 'PLAYLIST',
                                        sourceName: playlistContent.name,
                                      ),
                                    ),
                                  );
                                } finally {
                                  overlayCubit.setBusy(false);
                                }
                              },
                        icon: Icon(
                          Icons.play_arrow,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        Widget _buildVideosList(
          BuildContext context,
          PlaylistOverlayState overlayState,
        ) {
          if (overlayState.status == PlaylistOverlayStatus.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Error loading playlist',
                    style: TextStyle(color: Colors.red, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overlayState.error ?? 'Unknown error',
                    style: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<PlaylistOverlayCubit>().loadPlaylistVideos(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (overlayState.status == PlaylistOverlayStatus.loading) {
            return ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: 6,
              itemBuilder: (context, index) => _buildSkeletonVideoTile(context),
            );
          }

          if (overlayState.videos.isEmpty) {
            return const SizedBox.shrink();
          }

          return ListView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: overlayState.videos.length,
            itemBuilder: (context, i) => _buildVideoTile(
              context: context,
              overlayState: overlayState,
              video: overlayState.videos[i],
              trackNumber: i + 1,
              length: overlayState.videos.length,
            ),
          );
        }

        Widget _buildVideoTile({
          required BuildContext context,
          required PlaylistOverlayState overlayState,
          required Video video,
          required int trackNumber,
          required int length,
        }) {
          final track = StreamingData(
            videoId: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnailUrl: video.thumbnails.mediumResUrl,
            duration: video.duration,
          );

          final isPreparing = context.select<AudioPlayerCubit, bool>(
            (cubit) => cubit.state.isPreparing,
          );
          final disabled = overlayState.isBusy || isPreparing;
          final isStartingThis =
              overlayState.startingTrackId == track.videoId && overlayState.isBusy;

          return AbsorbPointer(
            absorbing: disabled,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(30),
                borderRadius: BorderRadius.vertical(
                  top: trackNumber == 0
                      ? const Radius.circular(33)
                      : const Radius.circular(6),
                  bottom: trackNumber == length - 1
                      ? const Radius.circular(33)
                      : const Radius.circular(6),
                ),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(50),
                  width: 1,
                ),
              ),
              child: isStartingThis
                  ? SizedBox(
                      height: 72,
                      child: Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(30),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: ExpressiveLoadingIndicator(
                              color: Theme.of(context).colorScheme.primary,
                              constraints: const BoxConstraints.tightFor(
                                width: 22,
                                height: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () async {
                        if (disabled) return;

                        final overlayCubit = context.read<PlaylistOverlayCubit>();
                        overlayCubit.beginStart(track.videoId);
                        try {
                          final playlistFull = overlayState.videos
                              .map(
                                (v) => StreamingData(
                                  videoId: v.id.value,
                                  title: v.title,
                                  artist: v.author,
                                  thumbnailUrl: v.thumbnails.highResUrl,
                                  duration: v.duration,
                                ),
                              )
                              .toList(growable: false);

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

                          if (track.thumbnailUrl != null &&
                              track.thumbnailUrl!.isNotEmpty) {
                            try {
                              await ImageCacheService().preloadImage(
                                track.thumbnailUrl!,
                              );
                            } catch (_) {}
                          }

                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => PlayerScreen(
                                title: track.title,
                                artist: track.artist,
                                imageUrl: track.thumbnailUrl,
                                duration: track.duration,
                                playlist: playlist,
                                initialIndex: cappedIndex,
                                sourceType: 'PLAYLIST',
                                sourceName: playlistContent.name,
                              ),
                            ),
                          );
                        } finally {
                          overlayCubit.endStart();
                        }
                      },
                      child: ListTile(
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: M3Container.c7SidedCookie(
                            width: 56,
                            height: 56,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: (track.thumbnailUrl != null &&
                                          track.thumbnailUrl!.isNotEmpty)
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: CachedNetworkImage(
                                            imageUrl: track.thumbnailUrl!,
                                            placeholder: (context, url) =>
                                                M3Container.c7SidedCookie(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withAlpha(30),
                                              child: Center(
                                                child: ExpressiveLoadingIndicator(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withAlpha(155),
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
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
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withAlpha(30),
                                            child: Icon(
                                              Icons.music_note,
                                              color: Theme.of(context)
                                                  .iconTheme
                                                  .color
                                                  ?.withAlpha(155),
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
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          video.author,
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withAlpha(178),
                            fontSize: 12,
                          ),
                        ),
                        trailing: (video.duration != null)
                            ? Text(
                                _formatDuration(video.duration!),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withAlpha((255 * 0.5).toInt()),
                                  fontSize: 12,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
            ),
          );
        }

        Widget _buildSkeletonVideoTile(BuildContext context) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withAlpha(50),
                width: 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ),
              ),
              title: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 10,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              trailing: Icon(
                Icons.play_arrow,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
            ),
          );
        }

        String _formatDuration(Duration duration) {
          String twoDigits(int n) => n.toString().padLeft(2, '0');
          final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
          final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
          return "$twoDigitMinutes:$twoDigitSeconds";
        }
      }

*/

