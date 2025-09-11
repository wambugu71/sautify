import 'dart:async';

import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:flutter/material.dart';
import 'package:sautifyv2/models/album_search_result.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class SearchProvider extends ChangeNotifier {
  final YTMusic _ytmusic = YTMusic();

  bool _initialized = false;
  bool _isLoading = false;
  String _query = '';
  String? _error;

  // Raw results from YTMusic (keep only needed fields by mapping to StreamingData)
  final List<StreamingData> _results = [];
  final List<String> _suggestions = [];
  final List<AlbumSearchResult> _albumResults = [];

  // Debounce timer for suggestions/search input
  Timer? _debounce;
  final Duration _debounceDuration = const Duration(milliseconds: 350);

  // Cancellation tokens for searches/suggestions to ignore stale responses
  int _searchGeneration = 0;
  int _suggestionGeneration = 0;

  SearchProvider() {
    _initialize();
  }

  // Getters
  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  String get query => _query;
  String? get error => _error;
  List<StreamingData> get results => List.unmodifiable(_results);
  List<String> get suggestions => List.unmodifiable(_suggestions);
  List<AlbumSearchResult> get albumResults => List.unmodifiable(_albumResults);

  Future<void> _initialize() async {
    try {
      await _ytmusic.initialize();
      _initialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to initialize search: $e';
      notifyListeners();
    }
  }

  void updateQuery(String value) {
    _query = value;
    // Schedule debounced suggestions fetch
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      fetchSuggestions(_query);
    });
    notifyListeners();
  }

  Future<void> fetchSuggestions([String? q]) async {
    final searchText = (q ?? _query).trim();
    if (searchText.isEmpty || !_initialized) {
      _suggestions.clear();
      notifyListeners();
      return;
    }

    final int token = ++_suggestionGeneration;
    try {
      final sugg = await _ytmusic.getSearchSuggestions(searchText);
      // Ignore stale responses
      if (token != _suggestionGeneration) return;

      _suggestions
        ..clear()
        ..addAll(sugg);
      notifyListeners();
    } catch (e) {
      // Non-fatal
    }
  }

  Future<void> search([String? q]) async {
    final searchText = (q ?? _query).trim();
    if (searchText.isEmpty || !_initialized) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    final int token = ++_searchGeneration;
    try {
      // Kick off both requests
      final songsFuture = _ytmusic.searchSongs(searchText);
      final albumsFuture = _ytmusic.searchAlbums(searchText);

      final songs = await songsFuture;
      // Ignore stale responses between awaits
      if (token != _searchGeneration) return;

      final albums = await albumsFuture;
      if (token != _searchGeneration) return;

      _results
        ..clear()
        ..addAll(
          songs.map((song) {
            final thumb = _pickBetterThumb(song.thumbnails);
            // Convert API duration (int? seconds) to Duration?
            final int? seconds = song.duration;
            final Duration? dur = seconds != null
                ? Duration(seconds: seconds)
                : null;

            return StreamingData(
              videoId: song.videoId,
              title: song.name,
              artist: song.artist.name,
              thumbnailUrl: thumb,
              duration: dur,
            );
          }),
        );

      _albumResults
        ..clear()
        ..addAll(
          albums.map((album) {
            final thumb = _pickBetterThumb(album.thumbnails);
            return AlbumSearchResult(
              albumId: album.albumId,
              playlistId: album.playlistId,
              title: album.name,
              artist: album.artist.name,
              thumbnailUrl: thumb,
            );
          }),
        );
    } catch (e) {
      if (token != _searchGeneration) return;
      _error = 'Search failed: $e';
    } finally {
      if (token == _searchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<StreamingData>> fetchAlbumTracks(String albumId) async {
    if (!_initialized) return [];
    try {
      final album = await _ytmusic.getAlbum(albumId);
      // Map tracks to StreamingData
      final tracks = album.songs.map((s) {
        final thumb = _pickBetterThumb(s.thumbnails);
        final int? seconds = s.duration;
        final Duration? dur = seconds != null
            ? Duration(seconds: seconds)
            : null;
        return StreamingData(
          videoId: s.videoId,
          title: s.name,
          artist: s.artist.name,
          thumbnailUrl: thumb,
          duration: dur,
        );
      }).toList();
      return tracks;
    } catch (e) {
      _error = 'Failed to load album: $e';
      notifyListeners();
      return [];
    }
  }

  // Prefer medium/high thumbnail: pick second if present, else last, else null
  String? _pickBetterThumb(List thumbnails) {
    if (thumbnails.isEmpty) return null;
    if (thumbnails.length >= 2) return thumbnails[1].url;
    return thumbnails.last.url;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
