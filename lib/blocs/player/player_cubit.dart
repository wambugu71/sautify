/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';

import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sautifyv2/blocs/theme/theme_cubit.dart';
import 'package:sautifyv2/services/lyrics_cache.dart';

import 'player_state.dart';

class PlayerCubit extends Cubit<PlayerState> {
  final ThemeCubit _themeCubit;
  final YTMusic _ytmusic = YTMusic();
  final Map<String, List<LyricLine>> _lyricsCache = {};
  final LyricsCache _lyricsPersistentCache = LyricsCache();
  bool _ytReady = false;

  PlayerCubit(this._themeCubit) : super(const PlayerState()) {
    _themeCubit.stream.listen((themeState) {
      if (themeState.primaryColors.isNotEmpty) {
        final primary = themeState.primaryColors[0];
        emit(state.copyWith(
          bgColors: [
            primary.withAlpha(200),
            primary,
            primary.withAlpha(50),
          ],
        ));
      }
    });
  }

  void toggleLyrics() {
    emit(state.copyWith(showLyrics: !state.showLyrics));
  }

  Future<void> _ensureYtReady() async {
    if (_ytReady) return;
    try {
      await _ytmusic.initialize();
      _ytReady = true;
    } catch (_) {}
  }

  Future<void> fetchLyrics(String videoId, String title, String artist) async {
    if (_lyricsCache.containsKey(videoId)) {
      emit(state.copyWith(
        lyrics: _lyricsCache[videoId],
        lyricsLoading: false,
        lyricsError: null,
        showLyrics: true,
      ));
      return;
    }

    // Try persisted offline cache first.
    final persisted = await _lyricsPersistentCache.get(videoId);
    if (persisted != null && persisted.lines.isNotEmpty) {
      _lyricsCache[videoId] = persisted.lines;
      emit(state.copyWith(
        lyrics: persisted.lines,
        lyricsSource: persisted.source,
        lyricsLoading: false,
        lyricsError: null,
        showLyrics: true,
      ));
      return;
    }

    emit(state.copyWith(
      lyricsLoading: true,
      lyricsError: null,
      lyrics: [],
      showLyrics: true,
    ));

    await _ensureYtReady();

    try {
      final synclyrics = await _ytmusic.getTimedLyrics(videoId);
      List<LyricLine> resolved = [];
      String? source;
      String? resolvedFromVideoId;

      if (synclyrics != null && synclyrics.timedLyricsData.isNotEmpty) {
        resolved = synclyrics.timedLyricsData
            .map((l) => LyricLine(
                  (l.lyricLine ?? '').toString(),
                  l.cueRange?.startTimeMilliseconds ?? 0,
                  l.cueRange?.endTimeMilliseconds ??
                      (l.cueRange?.startTimeMilliseconds ?? 0) + 2000,
                ))
            .where((l) => l.text.trim().isNotEmpty)
            .toList();
        source = synclyrics.sourceMessage;
        resolvedFromVideoId = videoId;
      }

      if (resolved.isEmpty) {
        final searchQuery = '$title $artist'.trim();
        if (searchQuery.isNotEmpty) {
          final searchResults = await _ytmusic.searchSongs(searchQuery);
          for (var i = 0; i < searchResults.length && i < 5; i++) {
            final altVid = searchResults[i].videoId;
            if (altVid.isNotEmpty && altVid != videoId) {
              final altLyrics = await _ytmusic.getTimedLyrics(altVid);
              if (altLyrics != null && altLyrics.timedLyricsData.isNotEmpty) {
                resolved = altLyrics.timedLyricsData
                    .map((l) => LyricLine(
                          (l.lyricLine ?? '').toString(),
                          l.cueRange?.startTimeMilliseconds ?? 0,
                          l.cueRange?.endTimeMilliseconds ??
                              (l.cueRange?.startTimeMilliseconds ?? 0) + 2000,
                        ))
                    .where((l) => l.text.trim().isNotEmpty)
                    .toList();
                source = altLyrics.sourceMessage;
                resolvedFromVideoId = altVid;
                break;
              }
            }
          }
        }
      }

      if (resolved.isEmpty) {
        emit(state.copyWith(
          lyricsError: 'Lyrics not available',
          lyricsLoading: false,
        ));
      } else {
        _lyricsCache[videoId] = resolved;
        unawaited(
            _lyricsPersistentCache.set(videoId, resolved, source: source));
        if (resolvedFromVideoId != null && resolvedFromVideoId != videoId) {
          final altId = resolvedFromVideoId;
          unawaited(
            _lyricsPersistentCache.set(altId, resolved, source: source),
          );
        }
        emit(state.copyWith(
          lyrics: resolved,
          lyricsSource: source,
          lyricsLoading: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        lyricsError: 'Failed to load lyrics',
        lyricsLoading: false,
      ));
    }
  }

  void updateActiveLyricIndex(int positionMs) {
    if (state.lyrics.isEmpty) return;

    int index = -1;
    for (int i = 0; i < state.lyrics.length; i++) {
      if (positionMs >= state.lyrics[i].startTimeMs &&
          positionMs < state.lyrics[i].endTimeMs) {
        index = i;
        break;
      }
    }

    if (index == -1) {
      for (int i = 0; i < state.lyrics.length; i++) {
        if (positionMs < state.lyrics[i].startTimeMs) {
          index = i - 1;
          break;
        }
      }
      if (index == -1 && positionMs >= state.lyrics.last.startTimeMs) {
        index = state.lyrics.length - 1;
      }
    }

    if (state.activeLyricIndex != index) {
      emit(state.copyWith(activeLyricIndex: index));
    }
  }
}

