import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/providers/library_provider.dart';
import 'package:sautifyv2/providers/playlist_provider.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
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

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          PlaylistProvider(widget.playlistContent.playlistId ?? ''),
      child: Scaffold(
        backgroundColor: bgcolor.withOpacity(0.95),
        body: SafeArea(
          child: Consumer<PlaylistProvider>(
            builder: (context, playlistProvider, child) {
              return Stack(
                children: [
                  // Background blur effect
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bgcolor.withOpacity(0.8), bgcolor],
                      ),
                    ),
                  ),

                  // Main content
                  SafeArea(
                    child: Column(
                      children: [
                        // Header with close button
                        _buildHeader(context),

                        // Playlist info with Play button
                        _buildPlaylistInfo(context, playlistProvider),

                        // Videos list
                        Expanded(child: _buildVideosList(playlistProvider)),
                      ],
                    ),
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
          Expanded(
            child: Text(
              'Playlist',
              style: TextStyle(
                color: txtcolor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
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
      child: Row(
        children: [
          // Playlist thumbnail
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cardcolor,
            ),
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

          const SizedBox(width: 16),

          // Playlist details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlistContent.name,
                  style: TextStyle(
                    color: txtcolor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.playlistContent.artistName,
                  style: TextStyle(
                    color: txtcolor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),

                // Play + Save buttons
                Row(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _busy,
                      builder: (context, busy, __) {
                        final disabled =
                            !hasTracks || busy || _audio.isPreparing.value;
                        return ElevatedButton.icon(
                          onPressed: disabled
                              ? null
                              : () async {
                                  if (busy || _audio.isPreparing.value) return;
                                  _busy.value = true;
                                  try {
                                    final playlist = provider.videos
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
                                    await _audio.stop();
                                    await _audio.loadPlaylist(
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
                              : const Icon(Icons.play_arrow),
                          label: disabled
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Play'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appbarcolor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 2),
                    Consumer<LibraryProvider>(
                      builder: (context, lib, _) {
                        final isSaved =
                            playlistId.isNotEmpty &&
                            lib.getPlaylists().any((p) => p.id == playlistId);
                        return OutlinedButton.icon(
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
                                          content: Text('Removed from Library'),
                                        ),
                                      );
                                    }
                                  } else {
                                    final tracks = provider.videos
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
                                    final saved = SavedPlaylist(
                                      id: playlistId,
                                      title: widget.playlistContent.name,
                                      artworkUrl:
                                          widget.playlistContent.thumbnailUrl,
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
                            isSaved ? Icons.favorite : Icons.favorite_border,
                            color: isSaved ? Colors.red : appbarcolor,
                          ),
                          label: Text(isSaved ? 'Saved' : 'Save'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isSaved ? Colors.red : appbarcolor,
                            side: BorderSide(color: appbarcolor),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
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
        itemCount: 6,
        itemBuilder: (context, index) => _buildSkeletonVideoTile(),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: provider.videos.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: txtcolor.withOpacity(0.1)),
      ),
      itemBuilder: (context, i) =>
          _buildVideoTile(provider, provider.videos[i], i + 1),
    );
  }

  Widget _buildVideoTile(
    PlaylistProvider provider,
    Video video,
    int trackNumber,
  ) {
    final track = StreamingData(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, busy, __) {
        final disabled = busy || _audio.isPreparing.value;
        return Opacity(
          opacity: disabled ? 0.6 : 1,
          child: AbsorbPointer(
            absorbing: disabled,
            child: Container(
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
                    color: bgcolor,
                  ),
                  child:
                      track.thumbnailUrl != null &&
                          track.thumbnailUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: track.thumbnailUrl!,
                            fit: BoxFit.cover,
                            width: 60,
                            height: 60,
                          ),
                        )
                      : Icon(
                          Icons.music_note,
                          color: iconcolor.withOpacity(0.6),
                        ),
                ),
                title: Text(
                  track.title,
                  style: TextStyle(
                    color: txtcolor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.author,
                      style: TextStyle(
                        color: txtcolor.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    if (video.duration != null)
                      Text(
                        _formatDuration(video.duration!),
                        style: TextStyle(
                          color: txtcolor.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                trailing: disabled
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            appbarcolor,
                          ),
                        ),
                      )
                    : Icon(Icons.play_arrow, color: appbarcolor, size: 28),
                onTap: () async {
                  if (busy || _audio.isPreparing.value) return;
                  _busy.value = true;
                  try {
                    final playlist = provider.videos
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
                    await _audio.stop();
                    await _audio.loadPlaylist(
                      playlist,
                      initialIndex: trackNumber - 1,
                      autoPlay: true,
                      sourceType: 'PLAYLIST',
                      sourceName: widget.playlistContent.name,
                    );
                    if (mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PlayerScreen(
                            title: track.title,
                            artist: track.artist,
                            imageUrl: track.thumbnailUrl,
                            duration: track.duration,
                          ),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) _busy.value = false;
                  }
                },
              ),
            ),
          ), // close AbsorbPointer
        ); // close Opacity
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
