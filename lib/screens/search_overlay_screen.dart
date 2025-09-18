/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:async';

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
import 'package:sautifyv2/services/settings_service.dart';
import 'package:sautifyv2/widgets/mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SearchOverlayScreen extends StatefulWidget {
  const SearchOverlayScreen({super.key});

  @override
  State<SearchOverlayScreen> createState() => _SearchOverlayScreenState();
}

class _SearchOverlayScreenState extends State<SearchOverlayScreen> {
  final ValueNotifier<bool> _busy = ValueNotifier(false);
  final ValueNotifier<String?> _loadingAlbumId = ValueNotifier<String?>(null);
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  static const _recentKey = 'recent_searches';
  static const _recentMax = 10;
  List<String> _recent = <String>[];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _busy.dispose();
    _loadingAlbumId.dispose();
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      // Respect setting: if disabled, do not load or show recents
      final settings = SettingsService();
      if (settings.isReady && !settings.showRecentSearches) return;
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_recentKey) ?? <String>[];
      setState(() {
        _recent = list.take(_recentMax).toList();
      });
    } catch (_) {}
  }

  Future<void> _persistRecent() async {
    try {
      final settings = SettingsService();
      if (settings.isReady && !settings.showRecentSearches) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, _recent);
    } catch (_) {}
  }

  Future<void> _addRecent(String q) async {
    final settings = SettingsService();
    if (settings.isReady && !settings.showRecentSearches) return;
    final query = q.trim();
    if (query.isEmpty) return;
    // Move to front, keep unique (case-insensitive)
    _recent.removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    _recent.insert(0, query);
    if (_recent.length > _recentMax) {
      _recent = _recent.take(_recentMax).toList();
    }
    setState(() {});
    await _persistRecent();
  }

  Future<void> _removeRecent(String q) async {
    final settings = SettingsService();
    if (settings.isReady && !settings.showRecentSearches) return;
    _recent.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    setState(() {});
    await _persistRecent();
  }

  Future<void> _clearRecent() async {
    final settings = SettingsService();
    if (settings.isReady && !settings.showRecentSearches) return;
    _recent.clear();
    setState(() {});
    await _persistRecent();
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
          final settings = context.watch<SettingsService>();
          // If suggestions are disabled, ensure they are cleared once
          if (!settings.showSearchSuggestions) {
            final p = Provider.of<SearchProvider>(context, listen: false);
            if (p.suggestions.isNotEmpty) {
              // Clear suggestions
              p.fetchSuggestions('');
            }
          }

          return Scaffold(
            backgroundColor: bgcolor,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: Stack(
                children: [
                  // Base content (non-positioned so Stack gets proper size)
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: contentBottomPadding),
                      child: Column(
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 8),
                          _buildSearchBar(context),
                          const SizedBox(height: 8),
                          // Suggestions (top 3) and Albums are hidden while typing to avoid overflow
                          if (!isKeyboardOpen && settings.showSearchSuggestions)
                            _buildSuggestionsSection(),
                          if (!isKeyboardOpen) const SizedBox(height: 8),
                          if (!isKeyboardOpen) _buildAlbumsSection(),
                          if (!isKeyboardOpen) const SizedBox(height: 8),
                          Expanded(child: _buildResults()),
                        ],
                      ),
                    ),
                  ),
                  // Mini Player overlay; lifted above the keyboard if open
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(bottom: bottomInset * 0.01),
                      child: const MiniPlayer(),
                    ),
                  ),
                  // Loading overlay on top of everything (tracks & albums taps)
                  _buildLoadingOverlay(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    // Disabled global overlay; per-album tile overlay is used instead.
    return const SizedBox.shrink();
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
          final settings = context.watch<SettingsService>();
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
                    color: cardcolor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: appbarcolor, width: 1),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    onChanged: (v) {
                      if (settings.showSearchSuggestions) {
                        provider.updateQuery(v);
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () {
                            provider.fetchSuggestions(v);
                          },
                        );
                      } else {
                        _debounce?.cancel();
                      }
                    },
                    onSubmitted: (v) async {
                      await _addRecent(v);
                      provider.search(v);
                    },
                    style: TextStyle(color: txtcolor),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums',
                      hintStyle: TextStyle(color: txtcolor.withOpacity(0.7)),
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
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (provider.query.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear',
                                    icon: Icon(Icons.clear, color: iconcolor),
                                    onPressed: () {
                                      _controller.clear();
                                      provider.updateQuery('');
                                      provider.fetchSuggestions('');
                                      _focusNode.requestFocus();
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Search',
                                  onPressed: () async {
                                    await _addRecent(provider.query);
                                    provider.search();
                                  },
                                  icon: Icon(
                                    Icons.arrow_forward,
                                    color: iconcolor,
                                  ),
                                ),
                              ],
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: provider.isLoading
                    ? Padding(
                        key: const ValueKey('linear_loading'),
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: appbarcolor,
                          backgroundColor: cardcolor,
                        ),
                      )
                    : const SizedBox(key: ValueKey('no_loading'), height: 8),
              ),
              if (settings.showRecentSearches) _buildRecentSection(provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecentSection(SearchProvider provider) {
    if (_recent.isEmpty) return const SizedBox.shrink();
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
                    color: txtcolor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _recent.isEmpty ? null : _clearRecent,
                  child: Text('Clear', style: TextStyle(color: appbarcolor)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recent.map((q) {
                return GestureDetector(
                  onLongPress: () => _removeRecent(q),
                  child: ActionChip(
                    backgroundColor: cardcolor,
                    label: Text(q, style: TextStyle(color: txtcolor)),
                    avatar: Icon(Icons.history, color: iconcolor, size: 18),
                    onPressed: () async {
                      _controller.text = q;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      provider.updateQuery(q);
                      await _addRecent(q);
                      provider.search(q);
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
                    return ValueListenableBuilder<String?>(
                      valueListenable: _loadingAlbumId,
                      builder: (context, loadingId, __) {
                        final isLoadingThis = loadingId == album.albumId;
                        return AbsorbPointer(
                          absorbing: isLoadingThis,
                          child: GestureDetector(
                            onTap: () async {
                              if (_loadingAlbumId.value != null ||
                                  audioService.isPreparing.value)
                                return;
                              _loadingAlbumId.value = album.albumId;
                              try {
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
                                if (mounted) _loadingAlbumId.value = null;
                              }
                            },
                            onLongPress: () async {
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
                                      content: Text(
                                        'Album removed from Library',
                                      ),
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
                                                    imageUrl:
                                                        album.thumbnailUrl!,
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
                                                            a.id ==
                                                            album.albumId,
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
                                                        final saved =
                                                            SavedAlbum(
                                                              id: album.albumId,
                                                              title:
                                                                  album.title,
                                                              artist:
                                                                  album.artist,
                                                              artworkUrl: album
                                                                  .thumbnailUrl,
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
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    child: Container(
                                                      decoration:
                                                          const BoxDecoration(
                                                            color:
                                                                Colors.black26,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
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
                                            if (isLoadingThis)
                                              Container(
                                                width: double.infinity,
                                                height: double.infinity,
                                                color: Colors.black38,
                                                alignment: Alignment.center,
                                                child: SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 3,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(appbarcolor),
                                                  ),
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

          final mutablePlaylist = List<StreamingData>.from(list);
          Future.microtask(() async {
            try {
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
            } catch (e) {
              debugPrint('Background load failed: $e');
            }
          });

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

          if (mounted) _busy.value = false;
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
