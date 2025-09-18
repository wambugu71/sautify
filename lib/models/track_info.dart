/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:sautifyv2/models/streaming_model.dart';

/// Comprehensive track information model that combines all track details
/// for synchronized updates across the UI
class TrackInfo {
  final StreamingData? track;
  final int currentIndex;
  final int totalTracks;
  final bool isPlaying;
  final bool isShuffleEnabled;
  final String loopMode; // 'off', 'one', 'all'
  final Duration position;
  final Duration? duration;
  final double progress; // 0.0 to 1.0
  // New: where this queue is playing from
  final String? sourceName; // e.g., playlist/album name
  final String
  sourceType; // e.g., PLAYLIST, ALBUM, SEARCH, RECENTS, FAVORITES, QUEUE

  const TrackInfo({
    this.track,
    required this.currentIndex,
    required this.totalTracks,
    required this.isPlaying,
    required this.isShuffleEnabled,
    required this.loopMode,
    required this.position,
    this.duration,
    required this.progress,
    this.sourceName,
    this.sourceType = 'QUEUE',
  });

  // Convenience getters
  String get title => track?.title ?? '';
  String get artist => track?.artist ?? '';
  String? get thumbnailUrl => track?.thumbnailUrl;
  String? get videoId => track?.videoId;

  // Check if track info is available
  bool get hasTrack => track != null;

  // Track position in playlist (1-based)
  String get trackPosition =>
      hasTrack ? '${currentIndex + 1} of $totalTracks' : '';

  // Formatted duration
  String get formattedDuration =>
      duration != null ? _formatDuration(duration!) : '';
  String get formattedPosition => _formatDuration(position);

  // Progress percentage as string
  String get progressPercentage => '${(progress * 100).toInt()}%';

  TrackInfo copyWith({
    StreamingData? track,
    int? currentIndex,
    int? totalTracks,
    bool? isPlaying,
    bool? isShuffleEnabled,
    String? loopMode,
    Duration? position,
    Duration? duration,
    double? progress,
    String? sourceName,
    String? sourceType,
  }) {
    return TrackInfo(
      track: track ?? this.track,
      currentIndex: currentIndex ?? this.currentIndex,
      totalTracks: totalTracks ?? this.totalTracks,
      isPlaying: isPlaying ?? this.isPlaying,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      progress: progress ?? this.progress,
      sourceName: sourceName ?? this.sourceName,
      sourceType: sourceType ?? this.sourceType,
    );
  }

  static String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrackInfo &&
        other.track?.videoId == track?.videoId &&
        other.currentIndex == currentIndex &&
        other.totalTracks == totalTracks &&
        other.isPlaying == isPlaying &&
        other.isShuffleEnabled == isShuffleEnabled &&
        other.loopMode == loopMode &&
        other.position == position &&
        other.duration == duration &&
        other.progress == progress &&
        other.sourceName == sourceName &&
        other.sourceType == sourceType;
  }

  @override
  int get hashCode {
    return Object.hash(
      track?.videoId,
      currentIndex,
      totalTracks,
      isPlaying,
      isShuffleEnabled,
      loopMode,
      position,
      duration,
      progress,
      sourceName,
      sourceType,
    );
  }

  @override
  String toString() {
    return 'TrackInfo(title: $title, artist: $artist, index: $currentIndex/$totalTracks, playing: $isPlaying, progress: ${progressPercentage}, source: ${sourceType}:${sourceName ?? ''})';
  }
}
