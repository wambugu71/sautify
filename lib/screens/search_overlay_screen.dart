/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautifyv2/blocs/library/library_cubit.dart';
import 'package:sautifyv2/blocs/library/library_state.dart';
import 'package:sautifyv2/blocs/search/search_bloc.dart';
import 'package:sautifyv2/blocs/search/search_event.dart';
import 'package:sautifyv2/blocs/search/search_state.dart';
import 'package:sautifyv2/blocs/settings/settings_cubit.dart';
import 'package:sautifyv2/blocs/settings/settings_state.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/image_cache_service.dart'
    hide CachedNetworkImage;
import 'package:sautifyv2/widgets/mini_player.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SearchOverlayScreen extends StatelessWidget {
  const SearchOverlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;
    final contentBottomPadding = isKeyboardOpen ? 16.0 : 100.0;

    return BlocListener<SearchBloc, SearchState>(
      listener: (context, state) {
        if (state.error != null &&
            state.error!.toLowerCase().contains('timeout')) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: Colors.deepOrange,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  context.read<SearchBloc>().add(SearchSubmitted(state.query));
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Stack(
            children: [
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(bottom: contentBottomPadding),
                  child: Column(
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 8),
                      const SearchInputBar(),
                      const SizedBox(height: 8),
                      BlocBuilder<SettingsCubit, SettingsState>(
                        builder: (context, settingsState) {
                          if (!isKeyboardOpen &&
                              settingsState.showSearchSuggestions) {
                            return _buildSuggestionsSection(context);
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      if (!isKeyboardOpen) const SizedBox(height: 8),
                      if (!isKeyboardOpen) _buildAlbumsSection(context),
                      if (!isKeyboardOpen) const SizedBox(height: 8),
                      Expanded(child: _buildResults(context)),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
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
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).iconTheme.color,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
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

  Widget _buildSuggestionsSection(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final iconColor = Theme.of(context).iconTheme.color;

    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state.suggestions.isEmpty) return const SizedBox.shrink();

        final top3 = state.suggestions.take(3).toList();
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: top3.map((s) {
                return ActionChip(
                  backgroundColor: primaryColor.withAlpha(30),
                  side: BorderSide(color: primaryColor.withAlpha(50), width: 1),
                  label: Text(s, style: TextStyle(color: textColor)),
                  avatar: Icon(Icons.search, color: iconColor, size: 18),
                  onPressed: () {
                    context.read<SearchBloc>().add(SearchQueryChanged(s));
                    context.read<SearchBloc>().add(SearchSubmitted(s));
                    context.read<SearchBloc>().add(SearchRecentAdded(s));
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsSection(BuildContext context) {
    final audioService = AudioPlayerService();
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final iconColor = Theme.of(context).iconTheme.color;

    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state.albumResults.isEmpty) {
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
                    color: textColor,
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
                  itemCount: state.albumResults.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final album = state.albumResults[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        try {
                          // Option A: Always interrupt whatever is loading/playing.
                          try {
                            await audioService.pause();
                          } catch (_) {}
                          try {
                            await audioService.stop();
                          } catch (_) {}

                          if (album.albumId.trim().isEmpty) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Couldn\'t open this album.'),
                              ),
                            );
                            return;
                          }

                          final tracksFull =
                              await context.read<SearchBloc>().fetchAlbumTracks(
                                    album.albumId,
                                    playlistId: album.playlistId,
                                  );
                          if (!context.mounted) return;
                          final tracks = tracksFull.length > 25
                              ? tracksFull.sublist(0, 25)
                              : tracksFull;
                          if (tracks.isEmpty) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Couldn\'t load album songs. Try again.'),
                              ),
                            );
                            return;
                          }

                          await audioService.replacePlaylist(
                            tracks,
                            initialIndex: 0,
                            autoPlay: true,
                            withTransition: true,
                            sourceType: 'ALBUM',
                            sourceName: album.title,
                          );

                          if (!context.mounted) return;
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
                        } catch (e) {
                          debugPrint('Album open failed: $e');
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Couldn\'t open this album. Try again.'),
                            ),
                          );
                        }
                      },
                      onLongPress: () async {
                        final libCubit = context.read<LibraryCubit>();
                        final isSaved = libCubit.state.albums
                            .any((a) => a.id == album.albumId);
                        if (isSaved) {
                          await libCubit.deleteAlbum(album.albumId);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Album removed from Library')),
                            );
                          }
                        } else {
                          final tracksFull =
                              await context.read<SearchBloc>().fetchAlbumTracks(
                                    album.albumId,
                                    playlistId: album.playlistId,
                                  );
                          final tracks = tracksFull.length > 25
                              ? tracksFull.sublist(0, 25)
                              : tracksFull;
                          if (tracks.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Couldn\'t load album songs to save. Try again.'),
                                ),
                              );
                            }
                            return;
                          }
                          final saved = SavedAlbum(
                            id: album.albumId,
                            title: album.title,
                            artist: album.artist,
                            artworkUrl: album.thumbnailUrl,
                            tracks: tracks,
                          );
                          await libCubit.saveAlbum(saved);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Album saved to Library')),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 120,
                        height: 200,
                        decoration: BoxDecoration(
                          color: primaryColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: primaryColor.withAlpha(50),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
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
                                            ? M3Container.square(
                                                child: CachedNetworkImage(
                                                  placeholder: (context, url) =>
                                                      M3Container.square(
                                                    child: LoadingIndicatorM3E(
                                                      containerColor:
                                                          primaryColor
                                                              .withAlpha(100),
                                                      color: primaryColor
                                                          .withAlpha(155),
                                                    ),
                                                  ),
                                                  imageUrl: album.thumbnailUrl!,
                                                  fit: BoxFit.cover,
                                                  width: 104,
                                                  height: 104,
                                                ),
                                              )
                                            : M3Container.square(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                child: Icon(Icons.album,
                                                    color: iconColor),
                                              ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: BlocBuilder<LibraryCubit,
                                              LibraryState>(
                                            builder: (context, libState) {
                                              final isSaved = libState.albums
                                                  .any((a) =>
                                                      a.id == album.albumId);
                                              return InkWell(
                                                onTap: () async {
                                                  final libCubit = context
                                                      .read<LibraryCubit>();
                                                  if (isSaved) {
                                                    await libCubit.deleteAlbum(
                                                        album.albumId);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                            content: Text(
                                                                'Album removed from Library')),
                                                      );
                                                    }
                                                  } else {
                                                    final tracks = await context
                                                        .read<SearchBloc>()
                                                        .fetchAlbumTracks(
                                                          album.albumId,
                                                          playlistId:
                                                              album.playlistId,
                                                        );
                                                    if (tracks.isEmpty) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .clearSnackBars();
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                                'Couldn\'t load album songs to save. Try again.'),
                                                          ),
                                                        );
                                                      }
                                                      return;
                                                    }
                                                    final saved = SavedAlbum(
                                                      id: album.albumId,
                                                      title: album.title,
                                                      artist: album.artist,
                                                      artworkUrl:
                                                          album.thumbnailUrl,
                                                      tracks: tracks,
                                                    );
                                                    await libCubit
                                                        .saveAlbum(saved);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                            content: Text(
                                                                'Album saved to Library')),
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
                                                    shape: BoxShape.circle,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  child: Icon(
                                                    isSaved
                                                        ? Icons.favorite
                                                        : Icons.favorite_border,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      album.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        album.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor
                                              ?.withAlpha((255 * 0.7).toInt()),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(BuildContext context) {
    final audioService = AudioPlayerService();
    final cardColor = Theme.of(context).cardColor;

    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                state.error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final isLoading =
            state.status == SearchStatus.loading && state.results.isEmpty;

        return Skeletonizer(
          enabled: isLoading,
          effect: ShimmerEffect(
            baseColor: cardColor,
            highlightColor: cardColor.withAlpha((255 * 0.6).toInt()),
            duration: const Duration(milliseconds: 1000),
          ),
          child: ListView.builder(
            itemCount: isLoading ? 10 : state.results.length,
            itemBuilder: (context, index) {
              if (isLoading) {
                return _buildSkeletonTile(context);
              }
              final track = state.results[index];
              return _buildResultTile(
                context,
                track,
                index,
                audioService,
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
    AudioPlayerService audioService,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final iconColor = Theme.of(context).iconTheme.color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: primaryColor.withAlpha(30),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor.withAlpha(50), width: 1),
      ),
      child: GestureDetector(
        onTap: () async {
          final query = context.read<SearchBloc>().state.query;

          // Ensure any currently-playing audio stops immediately, so we don't
          // show new metadata while old audio keeps playing.
          try {
            await audioService.pause();
          } catch (_) {}

          () async {
            try {
              await audioService.loadPlaylist(
                [track],
                initialIndex: 0,
                autoPlay: true,
                withTransition: true,
                sourceType: 'SEARCH',
                sourceName: query,
              );
            } catch (e) {
              debugPrint('Load failed: $e');
            }
          }();

          if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty) {
            try {
              await ImageCacheService().preloadImage(track.thumbnailUrl!);
            } catch (_) {}
          }

          if (context.mounted) {
            Navigator.of(context).pushReplacement(
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
        },
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      placeholder: (context, url) => M3Container.square(
                        child: LoadingIndicatorM3E(
                          containerColor: primaryColor.withAlpha(100),
                          color: primaryColor.withAlpha(155),
                        ),
                      ),
                      imageUrl: track.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: 60,
                      height: 60,
                    ),
                  )
                : Icon(
                    Icons.music_note,
                    color: iconColor?.withAlpha((255 * 0.6).toInt()),
                  ),
          ),
          title: Text(
            track.title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: TextStyle(
              color: textColor?.withAlpha((255 * 0.7).toInt()),
              fontSize: 12,
            ),
          ),
          trailing: Text(
            _formatDuration(track.duration ?? Duration.zero),
            style: TextStyle(
              color: textColor?.withAlpha((255 * 0.5).toInt()),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonTile(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: cardColor.withAlpha((255 * 0.7).toInt()),
          ),
        ),
        title: Container(
          height: 16,
          decoration: BoxDecoration(
            color: cardColor.withAlpha((255 * 0.7).toInt()),
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
                color: cardColor.withAlpha((255 * 0.5).toInt()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 10,
              width: 60,
              decoration: BoxDecoration(
                color: cardColor.withAlpha((255 * 0.5).toInt()),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.play_arrow,
          color: cardColor.withAlpha((255 * 0.7).toInt()),
        ),
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

class SearchInputBar extends StatefulWidget {
  const SearchInputBar({super.key});

  @override
  State<SearchInputBar> createState() => _SearchInputBarState();
}

class _SearchInputBarState extends State<SearchInputBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    final currentQuery = context.read<SearchBloc>().state.query;
    if (currentQuery.isNotEmpty) {
      _controller.text = currentQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).iconTheme.color;

    return BlocListener<SearchBloc, SearchState>(
      listenWhen: (previous, current) => previous.query != current.query,
      listener: (context, state) {
        if (_controller.text != state.query) {
          _controller.text = state.query;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, settingsState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.transparent,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            Theme.of(context).colorScheme.primary.withAlpha(50),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      onChanged: (v) {
                        context.read<SearchBloc>().add(SearchQueryChanged(v));
                      },
                      onSubmitted: (v) {
                        context.read<SearchBloc>().add(SearchSubmitted(v));
                        context.read<SearchBloc>().add(SearchRecentAdded(v));
                      },
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      cursorColor: Theme.of(context).colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists, albums',
                        hintStyle: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withAlpha((255 * 0.7).toInt()),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: iconColor,
                        ),
                        suffixIcon: BlocBuilder<SearchBloc, SearchState>(
                          builder: (context, state) {
                            if (state.status == SearchStatus.loading) {
                              return Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: LoadingIndicatorM3E(
                                    containerColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(100),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(155),
                                  ),
                                ),
                              );
                            }
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (state.query.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear',
                                    icon: Icon(Icons.clear, color: iconColor),
                                    onPressed: () {
                                      _controller.clear();
                                      context
                                          .read<SearchBloc>()
                                          .add(const SearchQueryChanged(''));
                                      _focusNode.requestFocus();
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Search',
                                  onPressed: () {
                                    context
                                        .read<SearchBloc>()
                                        .add(SearchSubmitted(_controller.text));
                                    context.read<SearchBloc>().add(
                                        SearchRecentAdded(_controller.text));
                                  },
                                  icon: Icon(Icons.arrow_forward,
                                      color: iconColor),
                                ),
                              ],
                            );
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                if (settingsState.showRecentSearches)
                  _buildRecentSection(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentSection(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final iconColor = Theme.of(context).iconTheme.color;

    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state.recentSearches.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Text(
                      'Recent searches',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          context.read<SearchBloc>().add(SearchRecentCleared()),
                      child:
                          Text('Clear', style: TextStyle(color: primaryColor)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: state.recentSearches.map((q) {
                    return GestureDetector(
                      onLongPress: () => context
                          .read<SearchBloc>()
                          .add(SearchRecentRemoved(q)),
                      child: ActionChip(
                        backgroundColor: primaryColor.withAlpha(30),
                        side: BorderSide(
                          color: primaryColor.withAlpha(50),
                          width: 1,
                        ),
                        label: Text(q, style: TextStyle(color: textColor)),
                        avatar: Icon(Icons.history, color: iconColor, size: 18),
                        onPressed: () {
                          context.read<SearchBloc>().add(SearchQueryChanged(q));
                          context.read<SearchBloc>().add(SearchSubmitted(q));
                          context.read<SearchBloc>().add(SearchRecentAdded(q));
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
