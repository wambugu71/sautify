/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

class LoadingProgress {
  final int totalTracks;
  final int loadedTracks;
  final int failedTracks;
  final LoadingPhase phase;
  final Map<String, TrackLoadStatus> trackStatuses; // videoId -> status

  LoadingProgress({
    required this.totalTracks,
    required this.loadedTracks,
    required this.failedTracks,
    required this.phase,
    this.trackStatuses = const {},
  });

  // Computed properties
  int get remainingTracks => totalTracks - loadedTracks - failedTracks;
  double get percentage =>
      totalTracks > 0 ? (loadedTracks + failedTracks) / totalTracks : 0.0;
  bool get isComplete => loadedTracks + failedTracks >= totalTracks;
  String get percentageDisplay => '${(percentage * 100).toInt()}%';

  LoadingProgress copyWith({
    int? totalTracks,
    int? loadedTracks,
    int? failedTracks,
    LoadingPhase? phase,
    Map<String, TrackLoadStatus>? trackStatuses,
  }) {
    return LoadingProgress(
      totalTracks: totalTracks ?? this.totalTracks,
      loadedTracks: loadedTracks ?? this.loadedTracks,
      failedTracks: failedTracks ?? this.failedTracks,
      phase: phase ?? this.phase,
      trackStatuses: trackStatuses ?? this.trackStatuses,
    );
  }
}

enum LoadingPhase {
  initializing, // "Preparing playlist..."
  loading, // "Loading tracks..."
  complete, // "Ready to play"
  error, // "Failed to load"
}

enum TrackLoadStatus {
  pending, // Not started
  loading, // Currently fetching
  loaded, // Successfully loaded
  failed, // Failed to load
}
