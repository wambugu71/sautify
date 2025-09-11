import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/providers/library_provider.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  final AudioPlayerService _audio = AudioPlayerService();
  bool _refreshedOnce = false;
  // Throttle rapid taps that start playback
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  void _playTracks(
    List<StreamingData> tracks, {
    int initialIndex = 0,
    String? sourceType,
    String? sourceName,
  }) async {
    if (tracks.isEmpty) return;
    // Prevent races from rapid taps or while preparing
    if (_busy.value || _audio.isPreparing.value) return;
    _busy.value = true;
    try {
      await _audio.stop();
      await _audio.loadPlaylist(
        tracks,
        initialIndex: initialIndex,
        autoPlay: true,
        sourceType: sourceType ?? 'QUEUE',
        sourceName: sourceName,
      );
    } finally {
      if (mounted) _busy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        if (!lib.isReady) {
          return Scaffold(
            backgroundColor: bgcolor,
            appBar: AppBar(
              title: const Text('Library'),
              backgroundColor: appbarcolor,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Ensure latest data is reflected when user navigates here
        if (!_refreshedOnce) {
          _refreshedOnce = true;
          // Post-frame to avoid build-loop
          WidgetsBinding.instance.addPostFrameCallback((_) => lib.refresh());
        }

        final recents = lib.getRecentPlays();
        final favs = lib.getFavorites();
        final playlists = lib.getPlaylists();
        final albums = lib.getAlbums();

        return Scaffold(
          backgroundColor: bgcolor,
          appBar: AppBar(
            title: const Text(
              'Library',
              style: TextStyle(
                fontFamily: 'asimovian',
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            backgroundColor: appbarcolor,
            foregroundColor: Colors.white,
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await lib.refresh();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: 100,
              ), // space for mini player
              children: [
                _buildSectionHeader(
                  context,
                  'Recently Played',
                  onPlayAll: recents.isNotEmpty
                      ? () => _playTracks(
                          recents,
                          sourceType: 'RECENTS',
                          sourceName: 'Recently Played',
                        )
                      : null,
                ),
                _buildHorizontalTrackList(
                  recents,
                  emptyLabel: 'No recents',
                  typeLabel: 'RECENT',
                ),
                _spacer(),
                _buildSectionHeader(
                  context,
                  'Favorites',
                  onPlayAll: favs.isNotEmpty
                      ? () => _playTracks(
                          favs,
                          sourceType: 'FAVORITES',
                          sourceName: 'Liked Songs',
                        )
                      : null,
                ),
                _buildHorizontalTrackList(
                  favs,
                  emptyLabel: 'No favorites',
                  typeLabel: 'FAVORITE',
                ),
                _spacer(),
                _buildSectionHeader(
                  context,
                  'Playlists',
                  onPlayAll: playlists.isNotEmpty
                      ? () {
                          final all = playlists
                              .expand((p) => p.tracks)
                              .toList();
                          _playTracks(
                            all,
                            sourceType: 'PLAYLIST',
                            sourceName: 'All Playlists',
                          );
                        }
                      : null,
                ),
                _buildHorizontalPlaylistList(playlists),
                _spacer(),
                _buildSectionHeader(
                  context,
                  'Albums',
                  onPlayAll: albums.isNotEmpty
                      ? () {
                          final all = albums.expand((a) => a.tracks).toList();
                          _playTracks(
                            all,
                            sourceType: 'ALBUM',
                            sourceName: 'All Albums',
                          );
                        }
                      : null,
                ),
                _buildHorizontalAlbumList(albums),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _spacer() => const SizedBox(height: 8);

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    VoidCallback? onPlayAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: txtcolor,
            ),
          ),
          if (onPlayAll != null)
            InkWell(
              onTap: onPlayAll,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: appbarcolor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Play all',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Tracks (Recents, Favorites) ---
  Widget _buildHorizontalTrackList(
    List<StreamingData> tracks, {
    required String emptyLabel,
    required String typeLabel,
  }) {
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          emptyLabel,
          style: TextStyle(color: txtcolor.withAlpha(180)),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final t = tracks[index];
          return _buildTrackCard(t, typeLabel: typeLabel);
        },
      ),
    );
  }

  Widget _buildTrackCard(StreamingData t, {required String typeLabel}) {
    return GestureDetector(
      onTap: () => _playTracks(
        [t],
        sourceType: typeLabel == 'RECENT'
            ? 'RECENTS'
            : (typeLabel == 'FAVORITE' ? 'FAVORITES' : 'QUEUE'),
        sourceName: typeLabel == 'RECENT'
            ? 'Recently Played'
            : (typeLabel == 'FAVORITE' ? 'Liked Songs' : null),
      ),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          color: cardcolor,
          elevation: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          color: Colors.grey[300],
                        ),
                        child:
                            (t.thumbnailUrl != null &&
                                t.thumbnailUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: t.thumbnailUrl!,
                                fit: BoxFit.cover,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                                errorWidget: const Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.music_note,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _typeChip(typeLabel),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: txtcolor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.artist,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
  }

  // --- Playlists ---
  Widget _buildHorizontalPlaylistList(List<SavedPlaylist> lists) {
    if (lists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No playlists',
          style: TextStyle(color: txtcolor.withAlpha(180)),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: lists.length,
        itemBuilder: (context, index) {
          final p = lists[index];
          return _buildEntityCard(
            title: p.title,
            subtitle: '${p.tracks.length} tracks',
            artworkUrl: p.artworkUrl,
            typeLabel: 'PLAYLIST',
            onTap: () => _playTracks(
              p.tracks,
              sourceType: 'PLAYLIST',
              sourceName: p.title,
            ),
          );
        },
      ),
    );
  }

  // --- Albums ---
  Widget _buildHorizontalAlbumList(List<SavedAlbum> albums) {
    if (albums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No albums',
          style: TextStyle(color: txtcolor.withAlpha(180)),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final a = albums[index];
          return _buildEntityCard(
            title: a.title,
            subtitle: a.artist,
            artworkUrl: a.artworkUrl,
            typeLabel: 'ALBUM',
            onTap: () =>
                _playTracks(a.tracks, sourceType: 'ALBUM', sourceName: a.title),
          );
        },
      ),
    );
  }

  Widget _buildEntityCard({
    required String title,
    required String subtitle,
    required String? artworkUrl,
    required String typeLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          color: cardcolor,
          elevation: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      color: Colors.grey[300],
                    ),
                    child: (artworkUrl != null && artworkUrl.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: artworkUrl,
                            fit: BoxFit.cover,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            errorWidget: const Center(
                              child: Icon(
                                Icons.music_note,
                                size: 40,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.music_note,
                              size: 40,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: txtcolor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      _typeChip(typeLabel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          color: Colors.green[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
