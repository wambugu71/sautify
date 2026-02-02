/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/services/connectivity_service.dart';
import 'package:sautifyv2/services/home_service.dart';
import 'package:sautifyv2/services/ytmusic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreenService implements HomeService {
  final YTMusicService _yt = YTMusicService.instance;
  bool _isLoading = false;
  HomeData? _homeData;
  static const Duration _netTimeout = Duration(seconds: 20);
  static const int _maxRetries = 2; // total attempts = _maxRetries + 1
  static const String _cacheKey = 'home_sections_cache_v1';
  static const Duration _staleAfter = Duration(minutes: 30);
  DateTime? _lastFetchAt;
  HomeDataSource _servedFrom = HomeDataSource.fresh; // default assumption

  HomeDataSource get servedFrom => _servedFrom;
  bool get isStale {
    if (_lastFetchAt == null) return true;
    return DateTime.now().difference(_lastFetchAt!) >= _staleAfter;
  }

  /// Manual refresh with optional longer timeout and ability to force network even if fresh cached exists.
  Future<void> refresh({Duration? timeout, bool forceNetwork = true}) async {
    // If currently loading, avoid stacking requests.
    if (_isLoading) return;
    _isLoading = true;
    try {
      final offline = !ConnectivityService().isOnline$.value;
      if (offline) {
        // Keep existing data; just mark servedFrom appropriately.
        if (_homeData != null) {
          _servedFrom = HomeDataSource.cache;
        }
        return;
      }
      final to = timeout ?? const Duration(seconds: 15);
      final rawSections = await _yt.getHomeSections(timeout: to);
      final hd = await compute(_parseHomeData, rawSections);
      _homeData = hd;
      _lastFetchAt = DateTime.now();
      _servedFrom = HomeDataSource.fresh;
      await _persistCached(hd);
    } catch (_) {
      // Preserve existing data, fallback to cache if completely empty
      if (_homeData == null) {
        final cached = await _loadCached();
        if (cached != null) {
          _homeData = cached;
          _servedFrom = HomeDataSource.cache;
        } else {
          _homeData = HomeData(sections: const []);
          _servedFrom = HomeDataSource.emptyFallback;
        }
      } else {
        // Existing data remains; mark stale source appropriately
        if (_servedFrom == HomeDataSource.fresh) {
          _servedFrom = HomeDataSource.cache; // degrade semantics
        }
      }
    } finally {
      _isLoading = false;
    }
  }

  @override
  Future<void> getHomeSections() async {
    _isLoading = true;
    try {
      // Fast-fail when offline to avoid indefinite hangs and skeletons
      final offline = !ConnectivityService().isOnline$.value;
      if (offline) {
        // Serve cached stale data if available when offline
        final cached = await _loadCached();
        if (cached != null) {
          _homeData = cached;
          _servedFrom = HomeDataSource.cache;
          return; // do not throw; UI can display cached content with offline banner
        }
        _servedFrom = HomeDataSource.emptyFallback;
        throw Exception('Offline');
      }
      // If we have fairly fresh data (< staleAfter), return it immediately while refreshing in background.
      final freshEnough =
          _lastFetchAt != null &&
          DateTime.now().difference(_lastFetchAt!) < _staleAfter;
      if (freshEnough && _homeData != null) {
        // Trigger silent background refresh
        _servedFrom = HomeDataSource.fresh;
        _refreshInBackground();
        return; // immediate return for snappy UI
      }

      // Active fetch with retry/backoff and escalating timeouts
      int attempt = 0;
      final perAttemptTimeouts = <Duration>[
        const Duration(seconds: 15),
        const Duration(seconds: 20),
        const Duration(seconds: 30),
      ];
      TimeoutException? lastTimeout;
      while (true) {
        attempt++;
        final to = (attempt - 1) < perAttemptTimeouts.length
            ? perAttemptTimeouts[attempt - 1]
            : perAttemptTimeouts.last;
        try {
          final rawSections = await _yt.getHomeSections(timeout: to);
          _homeData = await compute(_parseHomeData, rawSections);
          _lastFetchAt = DateTime.now();
          _servedFrom = HomeDataSource.fresh;
          await _persistCached(_homeData!);
          break;
        } on TimeoutException catch (e) {
          lastTimeout = e;
          if (kDebugMode) {
            debugPrint('Home sections timeout (attempt $attempt): $e');
          }
          if (attempt > _maxRetries) break;
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        } catch (_) {
          if (attempt > _maxRetries) break;
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
      if (_homeData == null) {
        // No success within attempts: prefer cached; else provide empty fallback and refresh in background
        final cached = await _loadCached();
        if (cached != null) {
          _homeData = cached;
          _servedFrom = HomeDataSource.cache;
        } else {
          _homeData = HomeData(sections: const []);
          _servedFrom = HomeDataSource.emptyFallback;
          // Background slow refresh with extended timeout; no exceptions bubble up
          _refreshInBackground(timeout: const Duration(seconds: 12));
          if (kDebugMode && lastTimeout != null) {
            debugPrint(
              'Home sections served fallback after timeouts: $lastTimeout',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching home sections: $e');
      }
      // As a last resort in unexpected errors, do not throwâ€”serve cache or empty and refresh later
      final cached = await _loadCached();
      if (cached != null) {
        _homeData = cached;
        _servedFrom = HomeDataSource.cache;
      } else {
        _homeData = HomeData(sections: const []);
        _servedFrom = HomeDataSource.emptyFallback;
      }
      _refreshInBackground(timeout: const Duration(seconds: 12));
    } finally {
      _isLoading = false;
    }
  }

  @override
  Future<void> initialize() async {
    try {
      // If offline, skip heavy init and return quickly
      final offline = !ConnectivityService().isOnline$.value;
      if (offline) return;
      await _yt.initializeIfNeeded(timeout: const Duration(seconds: 20));
      // Attempt silent cache load for initial UI.
      final cached = await _loadCached();
      if (cached != null) {
        _homeData = cached;
        _servedFrom = HomeDataSource.cache;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing YTMusic: $e');
      }
    }
  }

  @override
  HomeData? get homeData => _homeData;

  @override
  bool get isLoading => _isLoading;

  // Background refresh that does not alter loading state.
  void _refreshInBackground({Duration? timeout}) {
    () async {
      try {
        final rawSections = await _yt.getHomeSections(
          timeout: timeout ?? _netTimeout,
        );
        final hd = await compute(_parseHomeData, rawSections);
        _homeData = hd;
        _lastFetchAt = DateTime.now();
        _servedFrom = HomeDataSource.fresh;
        await _persistCached(hd);
      } catch (_) {
        // ignore
      }
    }();
  }

  Future<void> _persistCached(HomeData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMap = {
        'fetchedAt': DateTime.now().toIso8601String(),
        'sections': data.sections
            .map(
              (s) => {
                'title': s.title,
                'contents': s.contents
                    .map(
                      (c) => {
                        'name': c.name,
                        'artistName': c.artistName,
                        'videoId': c.videoId,
                        'thumbnailUrl': c.thumbnailUrl,
                        'type': c.type,
                        'playlistId': c.playlistId,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      };
      prefs.setString(_cacheKey, jsonEncode(jsonMap));
    } catch (_) {}
  }

  Future<HomeData?> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAtIso = map['fetchedAt'] as String?;
      if (fetchedAtIso != null) {
        final fetchedAt = DateTime.tryParse(fetchedAtIso);
        if (fetchedAt != null) {
          _lastFetchAt = fetchedAt;
          // Accept stale; age check only influences early-return logic
          // (UI can decide to show a small "stale" badge if needed).
        }
      }
      final sectionsRaw = map['sections'] as List<dynamic>?;
      if (sectionsRaw == null) return null;
      final sections = sectionsRaw.map((sec) {
        final title =
            (sec as Map<String, dynamic>)['title'] as String? ??
            'Unknown Section';
        final contentsRaw = sec['contents'] as List<dynamic>? ?? const [];
        final contents = contentsRaw.map((c) {
          final cm = c as Map<String, dynamic>;
          // Rehydrate using the same constructor signature
          return Contents(
            name: (cm['name'] as String?) ?? '',
            artistName: (cm['artistName'] as String?) ?? 'Unknown Artist',
            type: (cm['type'] as String?) ?? '',
            playlistId: cm['playlistId'] as String?,
            thumbnailUrl: (cm['thumbnailUrl'] as String?) ?? '',
            videoId: cm['videoId'] as String?,
          );
        }).toList();
        return Section(title: title, contents: contents);
      }).toList();
      return HomeData(sections: sections);
    } catch (_) {
      return null;
    }
  }
}

// Top-level function for compute
HomeData _parseHomeData(List<dynamic> rawSections) {
  return HomeData.fromYTMusicSections(rawSections);
}

enum HomeDataSource { fresh, cache, emptyFallback }

