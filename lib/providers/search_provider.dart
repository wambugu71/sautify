/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sautifyv2/models/album_search_result.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/ytmusic_service.dart';

class SearchProvider extends ChangeNotifier {
  final YTMusicService _yt = YTMusicService.instance;

  bool _initialized = false;
  bool _isLoading = false;
  String _query = '';
  String? _error;

  // Raw results from YTMusic (keep only needed fields by mapping to StreamingData)
  final List<StreamingData> _results = [];
  final List<String> _suggestions = [];
  final List<AlbumSearchResult> _albumResults = [];

  // RxDart streams for input and lifecycle
  final _querySubject = BehaviorSubject<String>.seeded('');
  final CompositeSubscription _subscriptions = CompositeSubscription();
  final Duration _debounceDuration = const Duration(milliseconds: 350);

  SearchProvider() {
    _initialize();
    _setupStreams();
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
      await _yt.initializeIfNeeded(timeout: const Duration(seconds: 15));
      _initialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to initialize search: $e';
      notifyListeners();
    }
  }

  void updateQuery(String value) {
    _query = value;
    // Push into the query stream; suggestions will debounce/cancel via Rx
    _querySubject.add(value);
    notifyListeners();
  }

  Future<void> fetchSuggestions([String? q]) async {
    final searchText = (q ?? _query).trim();
    if (searchText.isEmpty || !_initialized) {
      _suggestions.clear();
      notifyListeners();
      return;
    }
    try {
      final sugg = await _yt.getSearchSuggestions(
        searchText,
        timeout: const Duration(seconds: 4),
      );

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

    // Reentrancy guard & request identity token
    final int token = DateTime.now().microsecondsSinceEpoch;
    _activeSearchToken = token;

    _isLoading = true;
    _error = null;
    notifyListeners();

    // Fire both queries concurrently (reduces total wait time vs sequential)
    final songsFut = _yt
        .searchSongs(searchText, timeout: const Duration(seconds: 5))
        .then<List<dynamic>>((v) => v)
        .catchError((e, st) {
          if (e is TimeoutException) _songsTimedOutCount++;
          return <
            dynamic
          >[]; // treat failure as empty; we decide later if it's fatal
        });
    final albumsFut = _yt
        .searchAlbums(searchText, timeout: const Duration(seconds: 5))
        .then<List<dynamic>>((v) => v)
        .catchError((e, st) {
          if (e is TimeoutException) _albumsTimedOutCount++;
          return <dynamic>[];
        });

    bool overallTimedOut = false;
    List<dynamic> songs = <dynamic>[];
    List<dynamic> albums = <dynamic>[];
    try {
      final combined = await Future.wait<List<dynamic>>([songsFut, albumsFut])
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () {
              overallTimedOut = true;
              return <List<dynamic>>[]; // indicates total timeout
            },
          );
      if (combined.isNotEmpty) {
        songs = combined[0];
        albums = combined.length > 1 ? combined[1] : <dynamic>[];
      }
    } catch (e) {
      // Non-timeout unexpected errors bubble into _error below
      if (e is TimeoutException) overallTimedOut = true;
    }

    // If a newer search started meanwhile, abort applying these results.
    if (_activeSearchToken != token) {
      return; // newer search owns state updates
    }

    // Decide error vs partial results.
    final songsFailed = songs.isEmpty && _songsTimedOutCount > 0;
    final albumsFailed = albums.isEmpty && _albumsTimedOutCount > 0;
    final bothFailed = (songsFailed && albumsFailed) || overallTimedOut;

    if (bothFailed) {
      _results.clear();
      _albumResults.clear();
      _error = 'Search timed out. Please check your connection.';
    } else {
      // Map songs
      _results
        ..clear()
        ..addAll(
          songs.map((song) {
            final thumb = _pickBetterThumb(song.thumbnails);
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

      // If one side failed, surface a soft warning instead of hard error.
      if (songsFailed || albumsFailed) {
        _error = 'Partial results â€“ some items timed out.';
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<StreamingData>> fetchAlbumTracks(String albumId) async {
    if (!_initialized) return [];
    try {
      final album = await _yt.getAlbum(
        albumId,
        timeout: const Duration(seconds: 6),
      );
      // Defensive: album.songs may come in various dynamic shapes; force cast.
      final dynamic songsDynamic = (album as dynamic).songs;
      if (songsDynamic == null) return [];
      final List<dynamic> rawList = songsDynamic is List
          ? List<dynamic>.from(songsDynamic)
          : <dynamic>[];
      final tracks = <StreamingData>[];
      for (final s in rawList) {
        try {
          // If already a StreamingData (cached path), reuse.
          if (s is StreamingData) {
            tracks.add(s);
            continue;
          }
          final thumb = _pickBetterThumb((s as dynamic).thumbnails);
          final int? seconds = (s as dynamic).duration as int?;
          final Duration? dur = seconds != null
              ? Duration(seconds: seconds)
              : null;
          final videoId = (s as dynamic).videoId?.toString() ?? '';
          final title = (s as dynamic).name?.toString() ?? 'Unknown';
          final artistName =
              (s as dynamic).artist?.name?.toString() ?? 'Unknown';
          tracks.add(
            StreamingData(
              videoId: videoId,
              title: title,
              artist: artistName,
              thumbnailUrl: thumb,
              duration: dur,
            ),
          );
        } catch (_) {
          // Skip malformed entry
        }
      }
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
    _subscriptions.dispose();
    _querySubject.close();
    super.dispose();
  }

  void _setupStreams() {
    // Debounced, cancellable suggestions stream.
    // On every query change, wait for the debounce window and fetch suggestions.
    // switchMap ensures in-flight requests are ignored/cancelled when a new query arrives.
    final s = _querySubject
        .debounceTime(_debounceDuration)
        .map((q) => q.trim())
        .distinct()
        .where((q) => q.isNotEmpty)
        .switchMap<List<String>>((q) {
          Future<List<String>> fut;
          if (_initialized) {
            fut = _yt.getSearchSuggestions(
              q,
              timeout: const Duration(seconds: 4),
            );
          } else {
            fut = Future.value(<String>[]);
          }
          return Stream.fromFuture(fut).onErrorReturn(<String>[]);
        })
        .listen((sugg) {
          _suggestions
            ..clear()
            ..addAll(sugg);
          notifyListeners();
        });
    _subscriptions.add(s);
  }

  // State for concurrency & diagnostics
  int? _activeSearchToken;
  int _songsTimedOutCount = 0;
  int _albumsTimedOutCount = 0;

  /// Retry the last search with extended timeouts (useful after a timeout).
  Future<void> retrySearch() async {
    // Reset timeout counters for fresh attempt
    _songsTimedOutCount = 0;
    _albumsTimedOutCount = 0;
    // Re-run search with current query
    await search(_query);
  }
}

