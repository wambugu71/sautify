/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/db/hive_boxes.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class LibraryProvider extends ChangeNotifier {
  Box<String>? _favoritesBox;
  Box<String>? _recentPlaysBox;
  Box<String>? _playlistsBox;
  Box<String>? _albumsBox;
  final List<StreamSubscription> _subs = [];
  bool _isReady = false;

  // Bounds
  static const int _maxRecents = 100;
  static const int _maxFavorites = 500;
  DateTime _lastCompact = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isReady => _isReady;

  Future<void> init() async {
    await HiveBoxes.init();
    _favoritesBox = await Hive.openBox<String>(HiveBoxes.favorites);
    _recentPlaysBox = await Hive.openBox<String>(HiveBoxes.recentPlays);
    _playlistsBox = await Hive.openBox<String>(HiveBoxes.playlists);
    _albumsBox = await Hive.openBox<String>(HiveBoxes.albums);

    // Listen to box changes so UI updates when other layers write to Hive
    _subs.addAll([
      _favoritesBox!.watch().listen((_) => notifyListeners()),
      _recentPlaysBox!.watch().listen((_) => notifyListeners()),
      _playlistsBox!.watch().listen((_) => notifyListeners()),
      _albumsBox!.watch().listen((_) => notifyListeners()),
    ]);

    // Mark ready and notify for initial load
    _isReady = true;
    _enforceBoundsAndMaybeCompact();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_isReady) return;
    // Boxes are live; simply notifying listeners will re-query getters
    notifyListeners();
  }

  // Favorites (songs)
  List<StreamingData> getFavorites() {
    final values = _favoritesBox?.values ?? const Iterable.empty();
    return values
        .map(
          (e) => StreamingData.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> toggleFavorite(StreamingData track) async {
    final key = track.videoId;
    if (_favoritesBox!.containsKey(key)) {
      await _favoritesBox!.delete(key);
    } else {
      if (_favoritesBox!.length >= _maxFavorites) {
        // Remove an arbitrary oldest entry to keep bounds
        await _favoritesBox!.deleteAt(0);
      }
      await _favoritesBox!.put(key, jsonEncode(track.toJson()));
    }
    _enforceBoundsAndMaybeCompact();
    notifyListeners();
  }

  bool isFavorite(String videoId) =>
      _favoritesBox?.containsKey(videoId) ?? false;

  // Recently played (list, newest first, cap to 100)
  List<StreamingData> getRecentPlays() {
    final vals = _recentPlaysBox?.values ?? const Iterable.empty();
    final list = vals
        .map(
          (e) => StreamingData.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
    return list.reversed.toList();
  }

  Future<void> addRecentPlay(StreamingData track) async {
    // store with timestamp to keep order
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _recentPlaysBox!.put(key, jsonEncode(track.toJson()));
    if (_recentPlaysBox!.length > _maxRecents) {
      await _recentPlaysBox!.deleteAt(0);
    }
    _enforceBoundsAndMaybeCompact();
    notifyListeners();
  }

  // Playlists
  List<SavedPlaylist> getPlaylists() {
    final values = _playlistsBox?.values ?? const Iterable.empty();
    return values
        .map(
          (e) => SavedPlaylist.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> savePlaylist(SavedPlaylist playlist) async {
    await _playlistsBox!.put(playlist.id, jsonEncode(playlist.toJson()));
    _maybeCompact();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    await _playlistsBox!.delete(id);
    _maybeCompact();
    notifyListeners();
  }

  // Albums
  List<SavedAlbum> getAlbums() {
    final values = _albumsBox?.values ?? const Iterable.empty();
    return values
        .map((e) => SavedAlbum.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAlbum(SavedAlbum album) async {
    await _albumsBox!.put(album.id, jsonEncode(album.toJson()));
    _maybeCompact();
    notifyListeners();
  }

  Future<void> deleteAlbum(String id) async {
    await _albumsBox!.delete(id);
    _maybeCompact();
    notifyListeners();
  }

  // Library browsing helpers
  List<StreamingData> getAllSongs() {
    final songs = <StreamingData>[];

    // Favorites
    songs.addAll(getFavorites());

    // Recent plays
    songs.addAll(getRecentPlays());

    // Playlists
    final playlists = getPlaylists();
    for (final p in playlists) {
      songs.addAll(p.tracks);
    }

    // Albums
    final albums = getAlbums();
    for (final a in albums) {
      songs.addAll(a.tracks);
    }

    // Deduplicate by videoId, keep first-seen
    final seen = <String>{};
    final out = <StreamingData>[];
    for (final s in songs) {
      if (s.videoId.isEmpty) continue;
      if (seen.contains(s.videoId)) continue;
      seen.add(s.videoId);
      out.add(s);
    }
    return out;
  }

  List<String> getArtists() {
    final songs = getAllSongs();
    final set = <String>{};
    for (final s in songs) {
      final name = s.artist.trim();
      if (name.isNotEmpty) set.add(name);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<StreamingData> getSongsByArtist(String artist) {
    final needle = artist.trim().toLowerCase();
    return getAllSongs()
        .where((s) => s.artist.toLowerCase() == needle)
        .toList();
  }

  List<SavedAlbum> getAlbumsByArtist(String artist) {
    final needle = artist.trim().toLowerCase();
    return getAlbums().where((a) => a.artist.toLowerCase() == needle).toList();
  }

  List<StreamingData> getSongsByAlbumId(String albumId) {
    final values = _albumsBox?.get(albumId);
    if (values == null) return [];
    try {
      final album =
          SavedAlbum.fromJson(jsonDecode(values) as Map<String, dynamic>);
      return album.tracks;
    } catch (_) {
      return [];
    }
  }

  List<String> getGenres() {
    // Genre metadata isn't available in current storage; return empty list.
    return <String>[];
  }

  void _enforceBoundsAndMaybeCompact() {
    if (_recentPlaysBox != null) {
      while (_recentPlaysBox!.length > _maxRecents) {
        _recentPlaysBox!.deleteAt(0);
      }
    }
    if (_favoritesBox != null && _favoritesBox!.length > _maxFavorites) {
      // If overflowed, trim some oldest entries
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
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}

