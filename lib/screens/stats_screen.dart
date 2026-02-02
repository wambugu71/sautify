/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautifyv2/blocs/library/library_cubit.dart';
import 'package:sautifyv2/blocs/library/library_state.dart';
import 'package:sautifyv2/db/continue_listening_store.dart';
import 'package:sautifyv2/db/metadata_overrides_store.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/widgets/local_artwork_image.dart';

bool _isHttpUrl(String url) {
  final u = url.trim().toLowerCase();
  return u.startsWith('http://') || u.startsWith('https://');
}

bool _looksLikeFilePath(String urlOrPath) {
  final s = urlOrPath.trim().toLowerCase();
  if (s.startsWith('file://')) return true;
  if (s.startsWith('content://')) return false;
  return s.startsWith('/') || RegExp(r'^[a-z]:\\').hasMatch(s);
}

String _stripFileScheme(String s) {
  final trimmed = s.trim();
  if (trimmed.toLowerCase().startsWith('file://')) {
    return trimmed.substring('file://'.length);
  }
  return trimmed;
}

int? _tryParseLocalId(String videoId) {
  if (videoId.startsWith('local_')) {
    return int.tryParse(videoId.substring('local_'.length));
  }
  if (videoId.startsWith('local:')) {
    return int.tryParse(videoId.substring('local:'.length));
  }
  return null;
}

Widget _buildTrackArtwork(BuildContext context, StreamingData track) {
  const double size = 50;
  final theme = Theme.of(context);

  final placeholder = Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.music_note,
      color: theme.iconTheme.color?.withAlpha(100),
    ),
  );

  Widget child;
  if (track.isLocal && track.localId != null) {
    child = LocalArtworkImage(
      localId: track.localId!,
      placeholder: placeholder,
      fit: BoxFit.cover,
    );
  } else {
    final thumb = track.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      if (_looksLikeFilePath(thumb)) {
        child = Image.file(
          File(_stripFileScheme(thumb)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder,
        );
      } else if (_isHttpUrl(thumb)) {
        child = CachedNetworkImage(
          imageUrl: thumb,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => placeholder,
          placeholder: (_, __) => placeholder,
        );
      } else {
        child = placeholder;
      }
    } else {
      child = placeholder;
    }
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(width: size, height: size, child: child),
  );
}

enum _ListeningKey { recent, most, favorites }

class _ListeningCard extends StatefulWidget {
  const _ListeningCard();

  @override
  State<_ListeningCard> createState() => _ListeningCardState();
}

class _ListeningCardState extends State<_ListeningCard> {
  _ListeningKey _selected = _ListeningKey.recent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final sectionH = (screenH * 0.62).clamp(320.0, 640.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        height: sectionH,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.primary.withAlpha(25)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Listening',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_ListeningKey>(
                    segments: const [
                      ButtonSegment(
                        value: _ListeningKey.recent,
                        label: Text('Recently played'),
                      ),
                      ButtonSegment(
                        value: _ListeningKey.most,
                        label: Text('Most played'),
                      ),
                      ButtonSegment(
                        value: _ListeningKey.favorites,
                        label: Text('Favorites'),
                      ),
                    ],
                    selected: {_selected},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      setState(() => _selected = selection.first);
                    },
                    showSelectedIcon: false,
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selected == _ListeningKey.recent
                      ? const _RecentlyPlayedTab(key: ValueKey('recent'))
                      : _selected == _ListeningKey.most
                          ? const _MostPlayedTab(key: ValueKey('most'))
                          : const _FavoritesTab(key: ValueKey('favorites')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        if (!state.isReady) {
          return const Center(
            child: LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.contained,
              constraints: BoxConstraints(maxWidth: 50, maxHeight: 50),
            ),
          );
        }
        if (state.favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[800]),
                const SizedBox(height: 16),
                Text(
                  'No favorites yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final tracks = state.favorites;
        return ListView.builder(
          itemCount: tracks.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, index) {
            final track = MetadataOverridesStore.maybeApplySync(tracks[index]);
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
                leading: _buildTrackArtwork(context, track),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withAlpha(180),
                  ),
                ),
                onTap: () {
                  AudioPlayerService().loadPlaylist(
                    [track],
                    autoPlay: true,
                    sourceName: 'Favorites',
                    sourceType: 'FAVORITES',
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  Widget _continueListeningHeader(BuildContext context) {
    final listenable = ContinueListeningStore.listenable();
    if (listenable == null) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, __) {
        final session = ContinueListeningStore.loadSync();
        final track = session?.currentTrack;
        if (session == null || track == null) return const SizedBox.shrink();

        final applied = MetadataOverridesStore.maybeApplySync(track);
        final pos = session.position;
        final dur = applied.duration ?? Duration.zero;
        final ratio = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : null;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withAlpha(45),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: _buildTrackArtwork(context, applied),
                  title: Text(
                    applied.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    applied.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      AudioPlayerService().loadPlaylist(
                        session.playlist
                            .map(MetadataOverridesStore.maybeApplySync)
                            .toList(growable: false),
                        initialIndex: session.currentIndex,
                        autoPlay: true,
                        sourceType: session.sourceType ?? 'CONTINUE',
                        sourceName: session.sourceName ?? 'Continue listening',
                      );
                      Future.delayed(const Duration(milliseconds: 500), () {
                        AudioPlayerService().seek(session.position);
                      });
                    },
                    tooltip: 'Continue listening',
                  ),
                ),
                if (ratio != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor:
                            Theme.of(context).colorScheme.primary.withAlpha(30),
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

  Widget _listeningTabsSection(BuildContext context) {
    return const _ListeningCard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value != 'clear_history') return;
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Theme.of(context).cardColor,
                  title: Row(
                    children: [
                      Text(
                        'Clear History',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                      ),
                    ],
                  ),
                  content: Text(
                    'This will remove your recently played history! Are you sure you want to continue?',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withAlpha(200),
                    ),
                  ),
                  actions: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                context.read<LibraryCubit>().clearHistory();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear_history',
                child: Text('Clear listening history'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _continueListeningHeader(context),
          _listeningTabsSection(context),
        ],
      ),
    );
  }
}

class _RecentlyPlayedTab extends StatelessWidget {
  const _RecentlyPlayedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        if (!state.isReady) {
          return const Center(
            child: LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.contained,
              constraints: BoxConstraints(maxWidth: 50, maxHeight: 50),
            ),
          );
        }
        if (state.recentPlays.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[800]),
                const SizedBox(height: 16),
                Text(
                  'No recent plays yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        final tracks = state.recentPlays;
        return ListView.builder(
          itemCount: tracks.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, index) {
            final track = MetadataOverridesStore.maybeApplySync(tracks[index]);
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
                leading: _buildTrackArtwork(context, track),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withAlpha(180),
                  ),
                ),
                onTap: () {
                  AudioPlayerService().loadPlaylist(
                    [track],
                    autoPlay: true,
                    sourceName: 'Recently Played',
                    sourceType: 'HISTORY',
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _MostPlayedTab extends StatelessWidget {
  const _MostPlayedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        if (!state.isReady) {
          return const Center(
            child: LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.contained,
              constraints: BoxConstraints(maxWidth: 50, maxHeight: 50),
            ),
          );
        }
        if (state.mostPlayed.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 64, color: Colors.grey[800]),
                const SizedBox(height: 16),
                Text(
                  'No stats available yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        final stats = state.mostPlayed;
        return ListView.builder(
          itemCount: stats.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, index) {
            final stat = stats[index];
            final localId = _tryParseLocalId(stat.videoId);
            final isLocal = localId != null;
            final track = MetadataOverridesStore.maybeApplySync(
              StreamingData(
                videoId: stat.videoId,
                title: stat.title,
                artist: stat.artist,
                thumbnailUrl: stat.thumbnailUrl,
                isLocal: isLocal,
                localId: localId,
                streamUrl: isLocal
                    ? 'content://media/external/audio/media/$localId'
                    : null,
                isAvailable: true,
              ),
            );
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
                leading: _buildTrackArtwork(
                  context,
                  track,
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${track.artist}  ${stat.playCount} plays',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withAlpha(180),
                  ),
                ),
                trailing: Text(
                  '#${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                onTap: () {
                  AudioPlayerService().loadPlaylist(
                    [track],
                    autoPlay: true,
                    sourceName: 'Most Played',
                    sourceType: 'STATS',
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

