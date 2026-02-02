/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/db/hive_boxes.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/stats_model.dart';
import 'package:sautifyv2/models/streaming_model.dart';

import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  Box<String>? _favoritesBox;
  Box<String>? _recentPlaysBox;
  Box<String>? _playlistsBox;
  Box<String>? _albumsBox;
  Box<String>? _statsBox;
  final List<StreamSubscription> _subs = [];

  static const int _maxRecents = 100;
  static const int _maxFavorites = 500;
  DateTime _lastCompact = DateTime.fromMillisecondsSinceEpoch(0);

  LibraryCubit() : super(const LibraryState());

  Future<void> init() async {
    await HiveBoxes.init();
    _favoritesBox = await Hive.openBox<String>(HiveBoxes.favorites);
    _recentPlaysBox = await Hive.openBox<String>(HiveBoxes.recentPlays);
    _playlistsBox = await Hive.openBox<String>(HiveBoxes.playlists);
    _albumsBox = await Hive.openBox<String>(HiveBoxes.albums);
    _statsBox = await Hive.openBox<String>(HiveBoxes.stats);

    _subs.addAll([
      _favoritesBox!.watch().listen((_) => _updateState()),
      _recentPlaysBox!.watch().listen((_) => _updateState()),
      _playlistsBox!.watch().listen((_) => _updateState()),
      _albumsBox!.watch().listen((_) => _updateState()),
      _statsBox!.watch().listen((_) => _updateState()),
    ]);

    _enforceBoundsAndMaybeCompact();
    _updateState(isReady: true);
  }

  void _updateState({bool? isReady}) {
    emit(state.copyWith(
      favorites: _getFavorites(),
      recentPlays: _getRecentPlays(),
      playlists: _getPlaylists(),
      albums: _getAlbums(),
      mostPlayed: _getMostPlayed(),
      isReady: isReady,
    ));
  }

  List<StreamingData> _getFavorites() {
    final values = _favoritesBox?.values ?? const Iterable.empty();
    return values
        .map((e) =>
            StreamingData.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  List<StreamingData> _getRecentPlays() {
    final vals = _recentPlaysBox?.values ?? const Iterable.empty();
    final list = vals
        .map((e) =>
            StreamingData.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    return list.reversed.toList();
  }

  List<SavedPlaylist> _getPlaylists() {
    final values = _playlistsBox?.values ?? const Iterable.empty();
    return values
        .map((e) =>
            SavedPlaylist.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  List<SavedAlbum> _getAlbums() {
    final values = _albumsBox?.values ?? const Iterable.empty();
    return values
        .map((e) => SavedAlbum.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  List<SongStats> _getMostPlayed() {
    final values = _statsBox?.values ?? const Iterable.empty();
    final list = values
        .map((e) => SongStats.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.playCount.compareTo(a.playCount));
    return list.take(50).toList();
  }

  Future<void> toggleFavorite(StreamingData track) async {
    final key = track.videoId;
    if (_favoritesBox!.containsKey(key)) {
      await _favoritesBox!.delete(key);
    } else {
      if (_favoritesBox!.length >= _maxFavorites) {
        await _favoritesBox!.deleteAt(0);
      }
      await _favoritesBox!.put(key, jsonEncode(track.toJson()));
    }
    _enforceBoundsAndMaybeCompact();
  }

  bool isFavorite(String videoId) =>
      _favoritesBox?.containsKey(videoId) ?? false;

  Future<void> addRecent(StreamingData track) async {
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _recentPlaysBox!.put(key, jsonEncode(track.toJson()));
    _enforceBoundsAndMaybeCompact();
  }

  Future<void> incrementPlayCount(StreamingData track) async {
    final key = track.videoId;
    SongStats stats;
    if (_statsBox!.containsKey(key)) {
      final json = jsonDecode(_statsBox!.get(key)!);
      stats = SongStats.fromJson(json as Map<String, dynamic>);
      stats.playCount++;
      stats.lastPlayed = DateTime.now();
    } else {
      stats = SongStats(
        videoId: track.videoId,
        title: track.title,
        artist: track.artist,
        thumbnailUrl: track.thumbnailUrl,
        playCount: 1,
        lastPlayed: DateTime.now(),
      );
    }
    await _statsBox!.put(key, jsonEncode(stats.toJson()));
  }

  Future<void> clearHistory() async {
    await _recentPlaysBox!.clear();
    await _statsBox!.clear();
  }

  Future<void> addRecentPlay(StreamingData track) async {
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _recentPlaysBox!.put(key, jsonEncode(track.toJson()));
    if (_recentPlaysBox!.length > _maxRecents) {
      await _recentPlaysBox!.deleteAt(0);
    }
    _enforceBoundsAndMaybeCompact();
  }

  Future<void> savePlaylist(SavedPlaylist playlist) async {
    await _playlistsBox!.put(playlist.id, jsonEncode(playlist.toJson()));
    _maybeCompact();
  }

  Future<void> deletePlaylist(String id) async {
    await _playlistsBox!.delete(id);
    _maybeCompact();
  }

  Future<void> saveAlbum(SavedAlbum album) async {
    await _albumsBox!.put(album.id, jsonEncode(album.toJson()));
    _maybeCompact();
  }

  Future<void> deleteAlbum(String id) async {
    await _albumsBox!.delete(id);
    _maybeCompact();
  }

  void _enforceBoundsAndMaybeCompact() {
    if (_recentPlaysBox != null) {
      while (_recentPlaysBox!.length > _maxRecents) {
        _recentPlaysBox!.deleteAt(0);
      }
    }
    if (_favoritesBox != null && _favoritesBox!.length > _maxFavorites) {
      final overflow = _favoritesBox!.length - _maxFavorites;
      for (int i = 0; i < overflow; i++) {
        if (_favoritesBox!.isEmpty) break;
        _favoritesBox!.deleteAt(0);
      }
    }
    _maybeCompact();
  }

  void _maybeCompact() {
    final now = DateTime.now();
    if (now.difference(_lastCompact).inMinutes >= 10) {
      _favoritesBox?.compact();
      _recentPlaysBox?.compact();
      _playlistsBox?.compact();
      _albumsBox?.compact();
      _lastCompact = now;
    }
  }

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    return super.close();
  }
}

