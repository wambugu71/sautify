import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/providers/library_provider.dart';
import 'package:sautifyv2/providers/search_provider.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/widgets/mini_player.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SearchOverlayScreen extends StatefulWidget {
  const SearchOverlayScreen({super.key});

  @override
  State<SearchOverlayScreen> createState() => _SearchOverlayScreenState();
}

class _SearchOverlayScreenState extends State<SearchOverlayScreen> {
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchProvider(),
      child: Builder(
        builder: (context) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          final isKeyboardOpen = bottomInset > 0;
          final contentBottomPadding = isKeyboardOpen ? 16.0 : 100.0;

          return Scaffold(
            backgroundColor: bgcolor.withOpacity(0.95),
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: Stack(
                children: [
                  // Content with bottom padding for the mini player (reduced when keyboard is open)
                  Positioned.fill(
                    child: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: contentBottomPadding),
                        child: Column(
                          children: [
                            _buildHeader(context),
                            const SizedBox(height: 8),
                            _buildSearchBar(context),
                            const SizedBox(height: 8),
                            // Suggestions (top 3) and Albums are hidden while typing to avoid overflow
                            if (!isKeyboardOpen) _buildSuggestionsSection(),
                            if (!isKeyboardOpen) const SizedBox(height: 8),
                            if (!isKeyboardOpen) _buildAlbumsSection(),
                            if (!isKeyboardOpen) const SizedBox(height: 8),
                            Expanded(child: _buildResults()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Mini Player overlay; lifted above the keyboard if open
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(bottom: bottomInset * 0.01),
                      child: const MiniPlayer(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.keyboard_arrow_down, color: iconcolor, size: 32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search',
              style: TextStyle(
                color: txtcolor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<SearchProvider>(
        builder: (context, provider, _) {
          return TextField(
            onChanged: (v) {
              provider.updateQuery(v);
              provider.fetchSuggestions(v);
            },
            onSubmitted: (v) => provider.search(v),
            style: TextStyle(color: txtcolor),
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums',
              hintStyle: TextStyle(color: txtcolor.withOpacity(0.6)),
              prefixIcon: Icon(Icons.search, color: iconcolor),
              suffixIcon: provider.isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: appbarcolor,
                        ),
                      ),
                    )
                  : IconButton(
                      onPressed: () => provider.search(),
                      icon: Icon(Icons.arrow_forward, color: iconcolor),
                    ),
              filled: true,
              fillColor: cardcolor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        final suggs = provider.suggestions;
        if (suggs.isEmpty) return const SizedBox.shrink();

        final top3 = suggs.take(3).toList();
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: top3.map((s) {
                return ActionChip(
                  backgroundColor: cardcolor,
                  label: Text(s, style: TextStyle(color: txtcolor)),
                  avatar: Icon(Icons.search, color: iconcolor, size: 18),
                  onPressed: () {
                    final p = Provider.of<SearchProvider>(
                      context,
                      listen: false,
                    );
                    p.updateQuery(s);
                    p.search(s);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsSection() {
    final audioService = AudioPlayerService();
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        if (provider.albumResults.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: 210,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Albums',
                  style: TextStyle(
                    color: txtcolor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.albumResults.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final album = provider.albumResults[index];
                    return ValueListenableBuilder<bool>(
                      valueListenable: _busy,
                      builder: (context, busy, __) {
                        return GestureDetector(
                          onTap: () async {
                            if (busy || audioService.isPreparing.value) return;
                            _busy.value = true;
                            try {
                              // Fetch tracks, replace queue and play
                              final tracks = await provider.fetchAlbumTracks(
                                album.albumId,
                              );
                              if (tracks.isEmpty) return;

                              await audioService.stop();
                              await audioService.loadPlaylist(
                                tracks,
                                initialIndex: 0,
                                autoPlay: true,
                                sourceType: 'ALBUM',
                                sourceName: album.title,
                              );

                              if (context.mounted) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => PlayerScreen(
                                      title: tracks.first.title,
                                      artist: tracks.first.artist,
                                      imageUrl: tracks.first.thumbnailUrl,
                                      duration: tracks.first.duration,
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) _busy.value = false;
                            }
                          },
                          onLongPress: () async {
                            // Toggle save/unsave album to Library on long press
                            final lib = Provider.of<LibraryProvider>(
                              context,
                              listen: false,
                            );
                            final isSaved = lib.getAlbums().any(
                              (a) => a.id == album.albumId,
                            );
                            if (isSaved) {
                              await lib.deleteAlbum(album.albumId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Album removed from Library'),
                                  ),
                                );
                              }
                            } else {
                              final tracks = await provider.fetchAlbumTracks(
                                album.albumId,
                              );
                              if (tracks.isEmpty) return;
                              final saved = SavedAlbum(
                                id: album.albumId,
                                title: album.title,
                                artist: album.artist,
                                artworkUrl: album.thumbnailUrl,
                                tracks: tracks,
                              );
                              await lib.saveAlbum(saved);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Album saved to Library'),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              color: cardcolor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Stack(
                                        children: [
                                          album.thumbnailUrl != null
                                              ? CachedNetworkImage(
                                                  imageUrl: album.thumbnailUrl!,
                                                  fit: BoxFit.cover,
                                                  width: 104,
                                                  height: 104,
                                                )
                                              : Container(
                                                  color: bgcolor,
                                                  child: Icon(
                                                    Icons.album,
                                                    color: iconcolor,
                                                  ),
                                                ),
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: Consumer<LibraryProvider>(
                                              builder: (context, lib, __) {
                                                final isSaved = lib
                                                    .getAlbums()
                                                    .any(
                                                      (a) =>
                                                          a.id == album.albumId,
                                                    );
                                                return InkWell(
                                                  onTap: () async {
                                                    if (isSaved) {
                                                      await lib.deleteAlbum(
                                                        album.albumId,
                                                      );
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Album removed from Library',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    } else {
                                                      final tracks =
                                                          await provider
                                                              .fetchAlbumTracks(
                                                                album.albumId,
                                                              );
                                                      if (tracks.isEmpty)
                                                        return;
                                                      final saved = SavedAlbum(
                                                        id: album.albumId,
                                                        title: album.title,
                                                        artist: album.artist,
                                                        artworkUrl:
                                                            album.thumbnailUrl,
                                                        tracks: tracks,
                                                      );
                                                      await lib.saveAlbum(
                                                        saved,
                                                      );
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Album saved to Library',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Colors.black26,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    child: Icon(
                                                      isSaved
                                                          ? Icons.favorite
                                                          : Icons
                                                                .favorite_border,
                                                      color: isSaved
                                                          ? Colors.red
                                                          : Colors.white,
                                                      size: 18,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        album.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: txtcolor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        album.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: txtcolor.withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    final audioService = AudioPlayerService();
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        if (provider.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                provider.error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final isLoading = provider.isLoading && provider.results.isEmpty;

        return Skeletonizer(
          enabled: isLoading,
          effect: ShimmerEffect(
            baseColor: cardcolor,
            highlightColor: cardcolor.withOpacity(0.6),
            duration: const Duration(milliseconds: 1000),
          ),
          child: ListView.builder(
            itemCount: isLoading ? 10 : provider.results.length,
            itemBuilder: (context, index) {
              if (isLoading) {
                return _buildSkeletonTile();
              }
              final track = provider.results[index];
              return ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (context, busy, __) {
                  return Opacity(
                    opacity: (busy || audioService.isPreparing.value) ? 0.6 : 1,
                    child: AbsorbPointer(
                      absorbing: busy || audioService.isPreparing.value,
                      child: _buildResultTile(
                        context,
                        track,
                        index,
                        provider.results,
                        audioService,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildResultTile(
    BuildContext context,
    StreamingData track,
    int index,
    List<StreamingData> list,
    AudioPlayerService audioService,
  ) {
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
            color: bgcolor,
          ),
          child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnailUrl!,
                    fit: BoxFit.cover,
                    width: 60,
                    height: 60,
                  ),
                )
              : Icon(Icons.music_note, color: iconcolor.withOpacity(0.6)),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              track.artist,
              style: TextStyle(color: txtcolor.withOpacity(0.7), fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDuration(track.duration ?? Duration.zero),
              style: TextStyle(color: txtcolor.withOpacity(0.5), fontSize: 12),
            ),
          ],
        ),
        trailing: ValueListenableBuilder<bool>(
          valueListenable: _busy,
          builder: (context, busy, __) {
            final isDisabled = busy || audioService.isPreparing.value;
            return isDisabled
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(appbarcolor),
                    ),
                  )
                : Icon(Icons.play_arrow, color: appbarcolor, size: 28);
          },
        ),
        onTap: () async {
          if (_busy.value || audioService.isPreparing.value) return;
          _busy.value = true;
          try {
            // Replace current queue
            final mutablePlaylist = List<StreamingData>.from(list);
            await audioService.stop();
            await audioService.loadPlaylist(
              mutablePlaylist,
              initialIndex: index,
              autoPlay: true,
              sourceType: 'SEARCH',
              sourceName: Provider.of<SearchProvider>(
                context,
                listen: false,
              ).query,
            );

            // Open player screen by replacing the search overlay
            if (context.mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                    title: track.title,
                    artist: track.artist,
                    imageUrl: track.thumbnailUrl,
                    duration: track.duration,
                    // Do not pass playlist/videoId to avoid reloading
                  ),
                ),
              );
            }
          } finally {
            if (mounted) _busy.value = false;
          }
        },
      ),
    );
  }

  Widget _buildSkeletonTile() {
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
