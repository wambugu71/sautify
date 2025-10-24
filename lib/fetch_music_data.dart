/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'services/dio_client.dart';
import 'services/streaming_cache.dart';

class MusicStreamingService {
  static const int _maxConcurrentRequests = 5;
  static const int _retryAttempts = 2;
  static const Duration _requestTimeout = Duration(seconds: 40);
  static const Duration _nearExpiryRefreshThreshold = Duration(
    hours: 5,
    minutes: 30,
  ); // refresh in background when close

  final Dio _dio;
  final Semaphore _semaphore;
  final Map<String, StreamingData> _streamCache = {};
  // Deduplicate concurrent fetches for the same videoId
  final Map<String, Future<StreamingData?>> _inflight = {};
  final StreamingCache _persistent = StreamingCache();
  // Reuse a single YoutubeExplode instance to reduce overhead and reuse connections
  final YoutubeExplode _yt;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  MusicStreamingService()
    : _dio = DioClient.instance,
      _semaphore = Semaphore(_maxConcurrentRequests),
      _yt = YoutubeExplode() {
    _initConnectivity();
  }

  // Initialize connectivity-aware concurrency
  void _initConnectivity() {
    // Fire-and-forget; failures here should not impact playback
    () async {
      try {
        final results = await Connectivity().checkConnectivity();
        _adjustConcurrencyFor(results);
      } catch (_) {}
      try {
        _connSub = Connectivity().onConnectivityChanged.listen((results) {
          _adjustConcurrencyFor(results);
        });
      } catch (_) {}
    }();
  }

  void _adjustConcurrencyFor(List<ConnectivityResult> results) {
    // If any WiFi/Ethernet present, allow more concurrency; if only mobile, reduce.
    final hasWifi =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final newMax = hasWifi
        ? 6
        : hasMobile
        ? 3
        : 2; // very conservative when offline/unknown
    _semaphore.updateMaxCount(newMax);
  }

  /// Batch process multiple video IDs to get streaming URLs
  Future<BatchProcessingResult> batchGetStreamingUrls(
    List<String> videoIds, {
    StreamingQuality quality = StreamingQuality.medium,
  }) async {
    final stopwatch = Stopwatch()..start();
    final successful = <StreamingData>[];
    final failed = <String>[];
    final futures = <Future<void>>[];
    for (final id in videoIds) {
      futures.add(() async {
        final r = await _processVideoId(id, quality);
        if (r != null) {
          successful.add(r);
          _streamCache[id] = r;
        } else {
          failed.add(id);
        }
      }());
    }
    await Future.wait(futures, eagerError: false);

    stopwatch.stop();
    return BatchProcessingResult(
      successful: successful,
      failed: failed,
      processingTime: stopwatch.elapsed,
    );
  }

  /// Process single video ID with rate limiting
  Future<StreamingData?> _processVideoId(
    String videoId,
    StreamingQuality quality,
  ) async {
    // Check memory cache first
    StreamingData? cached = _streamCache[videoId];
    // If not in memory, try persistent cache
    cached ??= await _persistent.get(videoId);
    if (cached != null && !cached.isExpired) {
      // If near expiry, refresh in background but return cached now
      final age = DateTime.now().difference(cached.cachedAt);
      if (age >= _nearExpiryRefreshThreshold) {
        // ignore: discarded_futures
        _refreshInBackground(videoId, quality);
      }
      return cached;
    }

    // Deduplicate in-flight fetches for this videoId
    final existing = _inflight[videoId];
    if (existing != null) return existing;

    final completer = Completer<StreamingData?>();
    _inflight[videoId] = completer.future;

    () async {
      await _semaphore.acquire();
      try {
        final result = await _fetchStreamingDataHedgedWithRetry(
          videoId,
          quality,
        );
        if (result != null) {
          _streamCache[videoId] = result;
          // Persist to disk for next app start
          // ignore: discarded_futures
          _persistent.set(videoId, result);
        }
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _inflight.remove(videoId);
        _semaphore.release();
      }
    }();

    return completer.future;
  }

  /// Fetch streaming data with retry logic
  // Removed legacy single-path retry in favor of hedged with retry

  /// Hedged fetch with retry: race primary against fallback after a short delay and
  /// return the first non-null result. Reduces tail latency when primary is slow.
  Future<StreamingData?> _fetchStreamingDataHedgedWithRetry(
    String videoId,
    StreamingQuality quality,
  ) async {
    for (int attempt = 1; attempt <= _retryAttempts; attempt++) {
      try {
        final result = await _fetchStreamingDataHedged(videoId, quality);
        if (result != null) return result;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Hedged attempt $attempt failed for $videoId: $e');
        }
      }
      if (attempt < _retryAttempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }

  /// Fetch streaming data from multiple providers (public method)
  Future<StreamingData?> fetchStreamingData(
    String videoId,
    StreamingQuality quality,
  ) async {
    // If there is an inflight fetch, reuse it to avoid duplicate work
    final existing = _inflight[videoId];
    if (existing != null) return existing;
    final completer = Completer<StreamingData?>();
    _inflight[videoId] = completer.future;
    () async {
      try {
        final r = await _fetchStreamingDataHedgedWithRetry(videoId, quality);
        if (r != null) {
          _streamCache[videoId] = r;
          // ignore: discarded_futures
          _persistent.set(videoId, r);
        }
        completer.complete(r);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _inflight.remove(videoId);
      }
    }();
    return completer.future;
  }

  /// Force-refresh streaming data bypassing caches. Useful for recovering
  /// from expired links or transient load failures while playing.
  Future<StreamingData?> refreshStreamingData(
    String videoId,
    StreamingQuality quality,
  ) async {
    try {
      final fresh = await _fetchStreamingDataHedgedWithRetry(videoId, quality);
      if (fresh != null) {
        _streamCache[videoId] = fresh;
        // ignore: discarded_futures
        _persistent.set(videoId, fresh);
      } else {
        // Remove stale cache to avoid repeated failures
        _streamCache.remove(videoId);
        // ignore: discarded_futures
        _persistent.remove(videoId);
      }
      return fresh;
    } catch (_) {
      return null;
    }
  }

  // Removed in favor of hedged fetch

  /// Try YouTube Explode first (primary). If it fails/returns null, fall back
  /// to the HTTP Keith API. Previously this raced providers in parallel; now
  /// we prefer sequential fallback to avoid unnecessary extra requests.
  Future<StreamingData?> _fetchStreamingDataHedged(
    String videoId,
    StreamingQuality quality,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    StreamingData? winner;
    Object? primaryError;

    // Primary: Okatsu API
    try {
      winner = await _fetchFromOkatsu(videoId, quality);
    } catch (e) {
      primaryError = e;
      if (kDebugMode) {
        debugPrint('[resolve] Okatsu failed for $videoId: $e');
      }
    }

    // Fallback: YouTubeExplode
    if (winner == null) {
      try {
        winner = await _fetchFromYouTubeExplode(videoId, quality);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[resolve] YoutubeExplode failed for $videoId: $e');
        }
      }
    }

    sw.stop();
    if (kDebugMode) {
      debugPrint(
        '[resolve] vid=$videoId total=${sw.elapsedMilliseconds}ms primaryError=${primaryError != null} winner=${winner == null ? 'none' : winner.quality.toString()}',
      );
    }
    return winner;
  }

  void _refreshInBackground(String videoId, StreamingQuality quality) {
    () async {
      try {
        final refreshed = await _fetchStreamingDataHedgedWithRetry(
          videoId,
          quality,
        );
        if (refreshed != null) {
          _streamCache[videoId] = refreshed;
          // ignore: discarded_futures
          _persistent.set(videoId, refreshed);
        }
      } catch (_) {
        // ignore errors during background refresh
      }
    }();
  }

  /// Primary streaming service (your current API)
  // DISABLED: Vercel API completely failing - kept for reference
  // ignore: unused_element
  Future<StreamingData?> _fetchFromPrimaryService(
    String videoId,
    StreamingQuality quality,
  ) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';

    // Try multiple Keith API variants to improve resilience
    final List<String> endpoints = <String>[
      'https://apis-keith.vercel.app/download/dlmp3',
      'https://apis-keith.vercel.app/download/mp3',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await _dio.get(
          endpoint,
          queryParameters: {"url": youtubeUrl},
          options: Options(
            receiveTimeout: _requestTimeout,
            // Do not throw on 4xx/5xx; we'll handle statuses below
            validateStatus: (status) => true,
          ),
        );

        final status = response.statusCode ?? 0;
        if (status != 200 || response.data == null) {
          continue; // try next endpoint
        }

        final Map<String, dynamic> jsonResponse = response.data is String
            ? (jsonDecode(response.data as String) as Map<String, dynamic>)
            : (response.data as Map<String, dynamic>);

        // Support multiple shapes: {result:{data:{downloadUrl}}} or {result:"url"}
        Map<String, dynamic>? data;
        String? directUrl;
        try {
          final res = jsonResponse['result'];
          if (res is Map<String, dynamic>) {
            data = (res['data'] as Map<String, dynamic>?);
            directUrl = res['downloadUrl'] as String?;
          } else if (res is String) {
            directUrl = res;
          }
        } catch (_) {}

        final downloadUrl = directUrl ?? data?['downloadUrl'] as String?;
        if (downloadUrl == null) {
          continue; // try next endpoint
        }

        return StreamingData(
          videoId: videoId,
          title: (data?['title'] as String?) ?? 'Unknown',
          artist: (data?['artist'] as String?) ?? 'Unknown Artist',
          thumbnailUrl:
              data?['thumbnail'] as String?, // prefer provided artwork
          duration: (data?['duration'] != null)
              ? Duration(seconds: (data!['duration'] as num).toInt())
              : null,
          streamUrl: downloadUrl,
          quality: quality,
          isAvailable: true,
        );
      } catch (_) {
        // swallow and try next endpoint
        continue;
      }
    }

    return null; // all endpoints failed
  }

  /// New primary: Okatsu API provider
  Future<StreamingData?> _fetchFromOkatsu(
    String videoId,
    StreamingQuality quality,
  ) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    try {
      final response = await _dio.get(
        'https://okatsu-rolezapiiz.vercel.app/downloader/ytmp3',
        queryParameters: {'url': youtubeUrl},
        options: Options(
          receiveTimeout: _requestTimeout,
          validateStatus: (status) => true,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118 Safari/537.36',
          },
        ),
      );

      final status = response.statusCode ?? 0;
      if (status != 200 || response.data == null) return null;

      final Map<String, dynamic> jsonResponse = response.data is String
          ? (jsonDecode(response.data as String) as Map<String, dynamic>)
          : (response.data as Map<String, dynamic>);

      final bool ok = jsonResponse['status'] == true;
      final String? dl = jsonResponse['dl'] as String?;
      if (!ok || dl == null || dl.isEmpty || !dl.startsWith('http')) {
        return null;
      }

      final String title = (jsonResponse['title'] as String?) ?? 'Unknown';
      final String? thumb = jsonResponse['thumb'] as String?;
      final int? durationSec = (jsonResponse['duration'] as num?)?.toInt();

      final StreamingQuality inferredQ = _inferQualityFromUrl(dl) ?? quality;

      return StreamingData(
        videoId: videoId,
        title: title,
        artist: 'Unknown Artist',
        thumbnailUrl: thumb,
        duration: durationSec != null ? Duration(seconds: durationSec) : null,
        streamUrl: dl,
        quality: inferredQ,
        isAvailable: true,
      );
    } catch (_) {
      return null;
    }
  }

  StreamingQuality? _inferQualityFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('-320-') ||
        lower.contains('320kb') ||
        lower.contains('320.')) {
      return StreamingQuality.high;
    }
    if (lower.contains('-192-') ||
        lower.contains('192kb') ||
        lower.contains('192.')) {
      return StreamingQuality.medium;
    }
    if (lower.contains('-128-') ||
        lower.contains('128kb') ||
        lower.contains('128.')) {
      return StreamingQuality.low;
    }
    return null;
  }

  /// Fallback using YouTube Explode
  Future<StreamingData?> _fetchFromYouTubeExplode(
    String videoId,
    StreamingQuality quality,
  ) async {
    try {
      final videoFuture = _yt.videos.get(videoId);
      final manifestFuture = _yt.videos.streamsClient.getManifest(videoId);
      final results = await Future.wait([
        videoFuture,
        manifestFuture,
      ], eagerError: false);
      final video = results[0] as Video;
      final manifest = results[1] as StreamManifest;

      // Platform-aware container preference: iOS/macOS prefer mp4 (m4a),
      // Android/Windows/Linux prefer webm (opus). Fallback to any.
      final preferMp4 = Platform.isIOS || Platform.isMacOS;
      final audioOnly = manifest.audioOnly.toList();

      Iterable<AudioStreamInfo> preferred = audioOnly.where(
        (s) =>
            preferMp4 ? s.container.name == 'mp4' : s.container.name == 'webm',
      );
      Iterable<AudioStreamInfo> alt = audioOnly.where(
        (s) =>
            preferMp4 ? s.container.name != 'mp4' : s.container.name != 'webm',
      );

      int minBps;
      switch (quality) {
        case StreamingQuality.high:
          minBps = 256000;
          break;
        case StreamingQuality.medium:
          minBps = 128000;
          break;
        case StreamingQuality.low:
          minBps = 64000;
          break;
      }

      AudioStreamInfo? audioStream = preferred
          .where((s) => s.bitrate.bitsPerSecond >= minBps)
          .fold<AudioStreamInfo?>(null, (best, s) {
            if (best == null) return s;
            return s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond
                ? s
                : best;
          });

      // If none in preferred container, try alternatives with same threshold
      audioStream ??= alt
          .where((s) => s.bitrate.bitsPerSecond >= minBps)
          .fold<AudioStreamInfo?>(null, (best, s) {
            if (best == null) return s;
            return s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond
                ? s
                : best;
          });

      // Final fallback to absolutely highest bitrate
      audioStream ??= manifest.audioOnly.withHighestBitrate();

      return StreamingData(
        videoId: videoId,
        title: video.title,
        artist: video.author,
        thumbnailUrl: video.thumbnails.highResUrl, // prefer higher quality art
        duration: video.duration,
        streamUrl: audioStream.url.toString(),
        quality: quality,
        isAvailable: true,
      );
    } catch (_) {
      rethrow;
    }
  }

  /// Get cached streaming data
  StreamingData? getCachedStreamingData(String videoId) {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      return cached;
    }
    return null;
  }

  /// Clear expired cache entries
  void clearExpiredCache() {
    _streamCache.removeWhere((key, value) => value.isExpired);
  }

  /// Create batches for concurrent processing

  /// Dispose resources
  void dispose() {
    _streamCache.clear();
    // Optional: clear expired from persistent storage in the background
    // ignore: discarded_futures
    _persistent.clearExpired();
    // Close shared YoutubeExplode instance
    _yt.close();
    // Cancel connectivity subscription
    _connSub?.cancel();
    _connSub = null;
  }
}

/// Semaphore for rate limiting concurrent requests
class Semaphore {
  int _maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(int maxCount) : _maxCount = maxCount, _currentCount = maxCount;

  int get maxCount => _maxCount;

  void updateMaxCount(int newMax) {
    if (newMax < 1) newMax = 1;
    if (newMax == _maxCount) return;
    final delta = newMax - _maxCount;
    _maxCount = newMax;
    if (delta > 0) {
      // Increase available permits, also wake any waiters.
      _currentCount += delta;
      while (_currentCount > 0 && _waitQueue.isNotEmpty) {
        _currentCount--;
        final completer = _waitQueue.removeFirst();
        completer.complete();
      }
    } else {
      // Reduce free permits but do not revoke any acquired ones.
      if (_currentCount > _maxCount) {
        _currentCount = _maxCount;
      }
    }
  }

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      if (_currentCount < _maxCount) {
        _currentCount++;
      }
    }
  }
}

// Legacy function for backward compatibility
Future<String?> getDownloadUrl(String videoId) async {
  final service = MusicStreamingService();
  try {
    final result = await service._fetchStreamingDataHedgedWithRetry(
      videoId,
      StreamingQuality.medium,
    );
    return result?.streamUrl;
  } finally {
    service.dispose();
  }
}
