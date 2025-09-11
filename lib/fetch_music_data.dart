import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MusicStreamingService {
  static const int _maxConcurrentRequests = 3;
  static const int _retryAttempts = 2;
  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client _httpClient;
  final Semaphore _semaphore;
  final Map<String, StreamingData> _streamCache = {};

  MusicStreamingService()
    : _httpClient = http.Client(),
      _semaphore = Semaphore(_maxConcurrentRequests);

  /// Batch process multiple video IDs to get streaming URLs
  Future<BatchProcessingResult> batchGetStreamingUrls(
    List<String> videoIds, {
    StreamingQuality quality = StreamingQuality.medium,
  }) async {
    final stopwatch = Stopwatch()..start();
    final successful = <StreamingData>[];
    final failed = <String>[];

    // Process in batches of 3
    final batches = _createBatches(videoIds, _maxConcurrentRequests);

    for (final batch in batches) {
      final futures = batch.map((videoId) => _processVideoId(videoId, quality));
      final results = await Future.wait(futures, eagerError: false);

      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        if (result != null) {
          successful.add(result);
          _streamCache[batch[i]] = result;
        } else {
          failed.add(batch[i]);
        }
      }
    }

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
    // Check cache first
    if (_streamCache.containsKey(videoId)) {
      final cached = _streamCache[videoId]!;
      if (!cached.isExpired) {
        return cached;
      }
    }

    await _semaphore.acquire();

    try {
      return await _fetchStreamingDataWithRetry(videoId, quality);
    } finally {
      _semaphore.release();
    }
  }

  /// Fetch streaming data with retry logic
  Future<StreamingData?> _fetchStreamingDataWithRetry(
    String videoId,
    StreamingQuality quality,
  ) async {
    for (int attempt = 1; attempt <= _retryAttempts; attempt++) {
      try {
        final streamingData = await _fetchStreamingData(videoId, quality);
        if (streamingData != null) {
          return streamingData;
        }
      } catch (e) {
        print('Attempt $attempt failed for $videoId: $e');
        if (attempt == _retryAttempts) {
          print('All attempts failed for $videoId');
        } else {
          // Exponential backoff
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    return null;
  }

  /// Fetch streaming data from multiple providers (public method)
  Future<StreamingData?> fetchStreamingData(
    String videoId,
    StreamingQuality quality,
  ) async {
    return await _fetchStreamingData(videoId, quality);
  }

  /// Fetch streaming data from multiple providers
  Future<StreamingData?> _fetchStreamingData(
    String videoId,
    StreamingQuality quality,
  ) async {
    // Try primary service first
    try {
      final result = await _fetchFromPrimaryService(videoId, quality);
      if (result != null) return result;
    } catch (e) {
      print('Primary service failed for $videoId: $e');
    }

    // Fallback to YouTube Explode
    try {
      return await _fetchFromYouTubeExplode(videoId, quality);
    } catch (e) {
      print('YouTube Explode failed for $videoId: $e');
      return null;
    }
  }

  /// Primary streaming service (your current API)
  Future<StreamingData?> _fetchFromPrimaryService(
    String videoId,
    StreamingQuality quality,
  ) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    final response = await _httpClient
        .get(
          Uri.parse(
            "https://apis-keith.vercel.app/download/dlmp3?url=$youtubeUrl",
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final data = jsonResponse['result']?['data'] ?? {};
      final downloadUrl = data['downloadUrl'];

      if (downloadUrl != null) {
        return StreamingData(
          videoId: videoId,
          title: data['title'] ?? 'Unknown',
          artist: data['artist'] ?? 'Unknown Artist',
          thumbnailUrl: data['thumbnail'], // prefer provided artwork
          duration: data['duration'] != null
              ? Duration(seconds: (data['duration'] as num).toInt())
              : null,
          streamUrl: downloadUrl,
          quality: quality,
          isAvailable: true,
        );
      }
    }
    return null;
  }

  /// Fallback using YouTube Explode
  Future<StreamingData?> _fetchFromYouTubeExplode(
    String videoId,
    StreamingQuality quality,
  ) async {
    final yt = YoutubeExplode();

    try {
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);

      // Get audio stream based on quality preference
      AudioStreamInfo? audioStream;

      switch (quality) {
        case StreamingQuality.high:
          audioStream = manifest.audioOnly
              .where((s) => s.bitrate.bitsPerSecond >= 256000)
              .firstOrNull;
          break;
        case StreamingQuality.medium:
          audioStream = manifest.audioOnly
              .where((s) => s.bitrate.bitsPerSecond >= 128000)
              .firstOrNull;
          break;
        case StreamingQuality.low:
          audioStream = manifest.audioOnly
              .where((s) => s.bitrate.bitsPerSecond >= 64000)
              .firstOrNull;
          break;
      }

      // Fallback to best available
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
    } finally {
      yt.close();
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
  List<List<String>> _createBatches(List<String> items, int batchSize) {
    final batches = <List<String>>[];
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      batches.add(items.sublist(i, end));
    }
    return batches;
  }

  /// Dispose resources
  void dispose() {
    _httpClient.close();
    _streamCache.clear();
  }
}

/// Semaphore for rate limiting concurrent requests
class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

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
      _currentCount++;
    }
  }
}

// Legacy function for backward compatibility
Future<String?> getDownloadUrl(String videoId) async {
  final service = MusicStreamingService();
  try {
    final result = await service._fetchStreamingData(
      videoId,
      StreamingQuality.medium,
    );
    return result?.streamUrl;
  } finally {
    service.dispose();
  }
}
