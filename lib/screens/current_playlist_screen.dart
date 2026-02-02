/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_m3shapes/flutter_m3shapes.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:sautifyv2/blocs/audio_player_cubit.dart';
import 'package:sautifyv2/widgets/local_artwork_image.dart';

class CurrentPlaylistScreen extends StatefulWidget {
  const CurrentPlaylistScreen({super.key});

  @override
  State<CurrentPlaylistScreen> createState() => _CurrentPlaylistScreenState();
}

class _CurrentPlaylistScreenState extends State<CurrentPlaylistScreen> {
  static const double _itemExtent = 76.0;

  final ScrollController _scrollController = ScrollController();

  bool _isDraggingThumb = false;
  double _thumbDy = 0;
  int _thumbIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AudioPlayerCubit>().state;
      _scrollToIndex(state.currentIndex, animate: false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _looksLikeFilePath(String value) {
    return value.startsWith('file://') ||
        value.startsWith('/') ||
        value.contains('\\');
  }

  String _stripFileScheme(String value) {
    return value.startsWith('file://')
        ? value.replaceFirst('file://', '')
        : value;
  }

  void _scrollToIndex(int index, {required bool animate}) {
    if (!_scrollController.hasClients) return;
    final safeIndex = index.clamp(0, 1 << 30);
    final target = (safeIndex * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioCubit = context.read<AudioPlayerCubit>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Theme.of(context).iconTheme.color,
          ),
        ),
        title: Text(
          'Now Playing',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
            builder: (context, state) {
              return IconButton(
                onPressed: () => audioCubit.setShuffle(!state.isShuffleEnabled),
                icon: Icon(
                  Icons.shuffle,
                  color: state.isShuffleEnabled
                      ? colorScheme.primary
                      : Theme.of(context).iconTheme.color?.withAlpha(180),
                ),
              );
            },
          ),
          BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
            builder: (context, state) {
              final mode = state.loopMode;
              IconData icon;
              Color? color;
              if (mode == LoopMode.one) {
                icon = Icons.repeat_one;
                color = colorScheme.primary;
              } else if (mode == LoopMode.all) {
                icon = Icons.repeat;
                color = colorScheme.primary;
              } else {
                icon = Icons.repeat;
                color = Theme.of(context).iconTheme.color?.withAlpha(180);
              }
              return IconButton(
                onPressed: () {
                  final newMode = mode == LoopMode.off
                      ? LoopMode.all
                      : (mode == LoopMode.all ? LoopMode.one : LoopMode.off);
                  audioCubit.setLoopMode(newMode);
                },
                icon: Icon(icon, color: color),
              );
            },
          ),
          BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
            builder: (context, state) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${state.playlist.length} songs',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withAlpha(180),
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocListener<AudioPlayerCubit, AudioPlayerState>(
        listenWhen: (prev, curr) {
          if (prev.currentIndex != curr.currentIndex) return true;
          if (prev.playlist.length != curr.playlist.length) return true;
          return false;
        },
        listener: (context, state) {
          if (!mounted) return;
          if (state.playlist.isEmpty) return;
          _scrollToIndex(state.currentIndex, animate: true);
        },
        child: BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
          builder: (context, state) {
            final playlist = state.playlist;

            if (playlist.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: 64,
                      color: Theme.of(context).iconTheme.color?.withAlpha(100),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No songs in playlist',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.color?.withAlpha(180),
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              bottom: true,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bottomPad =
                          8 + MediaQuery.of(context).padding.bottom;
                      final viewHeight = constraints.maxHeight;

                      int indexFromDy(double dy) {
                        final usableHeight =
                            (viewHeight - bottomPad - 4).clamp(1.0, 1e9);
                        final normalized = (dy / usableHeight).clamp(0.0, 1.0);
                        final idx =
                            (normalized * (playlist.length - 1)).round();
                        return idx.clamp(0, playlist.length - 1);
                      }

                      double dyFromScrollOffset(double offset) {
                        final usableHeight =
                            (viewHeight - bottomPad - 4).clamp(1.0, 1e9);
                        if (!_scrollController.hasClients) return 0.0;
                        final position = _scrollController.position;
                        if (!position.hasContentDimensions) return 0.0;
                        final maxExtent = position.maxScrollExtent;
                        if (maxExtent <= 0) return 0.0;
                        final normalized = (offset / maxExtent).clamp(0.0, 1.0);
                        return normalized * usableHeight;
                      }

                      return Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.only(
                              top: 4,
                              bottom: bottomPad,
                            ),
                            itemExtent: _itemExtent,
                            itemCount: playlist.length,
                            itemBuilder: (context, index) {
                              final track = playlist[index];
                              final isCurrentTrack =
                                  index == state.currentIndex;

                              return Container(
                                color: isCurrentTrack
                                    ? colorScheme.primary.withAlpha(30)
                                    : Colors.transparent,
                                child: SizedBox(
                                  height: _itemExtent,
                                  child: ListTile(
                                    onTap: () async {
                                      final success = await audioCubit.seek(
                                        Duration.zero,
                                        index: index,
                                      );
                                      if (!context.mounted) return;

                                      if (success) {
                                        await audioCubit.service.play();
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Unable to play track. Please try again.',
                                            ),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                    leading: SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: M3Container.square(
                                        width: 56,
                                        height: 56,
                                        child: () {
                                          final placeholder =
                                              M3Container.square(
                                            color: Theme.of(context)
                                                .scaffoldBackgroundColor
                                                .withAlpha(155),
                                            child: LoadingIndicatorM3E(
                                              color: colorScheme.primary
                                                  .withAlpha(155),
                                            ),
                                          );

                                          final fallbackIcon = Icon(
                                            Icons.music_note,
                                            color: Theme.of(context)
                                                .iconTheme
                                                .color
                                                ?.withAlpha(180),
                                            size: 24,
                                          );

                                          if (track.isLocal &&
                                              track.localId != null) {
                                            return LocalArtworkImage(
                                              localId: track.localId!,
                                              placeholder: fallbackIcon,
                                            );
                                          }

                                          final url = track.thumbnailUrl;
                                          if (url == null || url.isEmpty) {
                                            return fallbackIcon;
                                          }

                                          if (_looksLikeFilePath(url)) {
                                            final path = _stripFileScheme(url);
                                            return Image.file(
                                              File(path),
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  fallbackIcon,
                                            );
                                          }

                                          return CachedNetworkImage(
                                            placeholder: (context, url) =>
                                                placeholder,
                                            imageUrl: url,
                                            fit: BoxFit.cover,
                                            width: 48,
                                            height: 48,
                                            errorWidget:
                                                (context, url, error) =>
                                                    fallbackIcon,
                                          );
                                        }(),
                                      ),
                                    ),
                                    title: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrentTrack
                                            ? colorScheme.primary
                                            : Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.color,
                                        fontSize: 15,
                                        fontWeight: isCurrentTrack
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrentTrack
                                            ? colorScheme.primary.withAlpha(180)
                                            : Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color
                                                ?.withAlpha(180),
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: isCurrentTrack
                                        ? SizedBox(
                                            width: 40,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: MiniMusicVisualizer(
                                                animate: true,
                                                color: colorScheme.primary,
                                                width: 4,
                                                height: 15,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                          Positioned(
                            right: 6,
                            top: 8,
                            bottom: bottomPad,
                            child: AnimatedBuilder(
                              animation: _scrollController,
                              builder: (context, _) {
                                final offset = _scrollController.hasClients
                                    ? _scrollController.offset
                                    : 0.0;
                                final handleDy = _isDraggingThumb
                                    ? _thumbDy
                                    : dyFromScrollOffset(offset);

                                return GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onVerticalDragStart: (d) {
                                    setState(() {
                                      _isDraggingThumb = true;
                                      _thumbDy = d.localPosition.dy;
                                      _thumbIndex = indexFromDy(_thumbDy);
                                    });
                                    _scrollToIndex(_thumbIndex, animate: false);
                                  },
                                  onVerticalDragUpdate: (d) {
                                    setState(() {
                                      _thumbDy = d.localPosition.dy;
                                      _thumbIndex = indexFromDy(_thumbDy);
                                    });
                                    _scrollToIndex(_thumbIndex, animate: false);
                                  },
                                  onVerticalDragEnd: (_) {
                                    setState(() {
                                      _isDraggingThumb = false;
                                    });
                                  },
                                  onVerticalDragCancel: () {
                                    setState(() {
                                      _isDraggingThumb = false;
                                    });
                                  },
                                  child: SizedBox(
                                    width: 36,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            width: 4,
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary
                                                  .withAlpha(60),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: handleDy.clamp(
                                              0.0, viewHeight - 24),
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary
                                                  .withAlpha(160),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                        if (_isDraggingThumb)
                                          Positioned(
                                            right: 26,
                                            top: (handleDy - 16)
                                                .clamp(0.0, viewHeight - 40),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.primary
                                                      .withAlpha(200),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${_thumbIndex + 1}',
                                                  style: TextStyle(
                                                    color:
                                                        colorScheme.onPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

