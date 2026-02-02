/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

class StreamingData {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Duration? duration;
  final String? streamUrl;
  final StreamingQuality quality;
  final DateTime cachedAt;
  final bool isAvailable;
  // New: local file indicator
  final bool isLocal;
  // New: local media store ID for artwork
  final int? localId;

  StreamingData({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.duration,
    this.streamUrl,
    this.quality = StreamingQuality.medium,
    DateTime? cachedAt,
    this.isAvailable = false,
    this.isLocal = false,
    this.localId,
  }) : cachedAt = cachedAt ?? DateTime.now();

  bool get isExpired {
    // Local files never expire
    if (isLocal) return false;
    // YouTube URLs typically expire after 6 hours
    return DateTime.now().difference(cachedAt).inHours > 6;
  }

  bool get isReady => streamUrl != null && isAvailable && !isExpired;

  StreamingData copyWith({
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    Duration? duration,
    String? streamUrl,
    StreamingQuality? quality,
    DateTime? cachedAt,
    bool? isAvailable,
    bool? isLocal,
    int? localId,
  }) {
    return StreamingData(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      streamUrl: streamUrl ?? this.streamUrl,
      quality: quality ?? this.quality,
      cachedAt: cachedAt ?? this.cachedAt,
      isAvailable: isAvailable ?? this.isAvailable,
      isLocal: isLocal ?? this.isLocal,
      localId: localId ?? this.localId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration?.inMilliseconds,
      'streamUrl': streamUrl,
      'quality': quality.index,
      'cachedAt': cachedAt.millisecondsSinceEpoch,
      'isAvailable': isAvailable,
      'isLocal': isLocal,
      'localId': localId,
    };
  }

  factory StreamingData.fromJson(Map<String, dynamic> json) {
    return StreamingData(
      videoId: json['videoId'],
      title: json['title'],
      artist: json['artist'],
      thumbnailUrl: json['thumbnailUrl'],
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null,
      streamUrl: json['streamUrl'],
      quality: StreamingQuality.values[json['quality'] ?? 1],
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
        json['cachedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isAvailable: json['isAvailable'] ?? false,
      isLocal: json['isLocal'] ?? false,
      localId: json['localId'],
    );
  }

  @override
  String toString() {
    return 'StreamingData(videoId: $videoId, title: $title, isReady: $isReady, isLocal: $isLocal)';
  }
}

enum StreamingQuality {
  low, // 128kbps
  medium, // 192kbps
  high, // 320kbps
}

class BatchProcessingResult {
  final List<StreamingData> successful;
  final List<String> failed;
  final Duration processingTime;

  BatchProcessingResult({
    required this.successful,
    required this.failed,
    required this.processingTime,
  });

  int get successCount => successful.length;
  int get failureCount => failed.length;
  int get totalCount => successCount + failureCount;
  double get successRate => totalCount > 0 ? successCount / totalCount : 0.0;
}

