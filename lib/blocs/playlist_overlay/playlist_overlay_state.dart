/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum PlaylistOverlayStatus { loading, ready, error }

class PlaylistOverlayState extends Equatable {
  final PlaylistOverlayStatus status;
  final List<Video> videos;
  final String? error;

  final bool isBusy;
  final String? startingTrackId;

  const PlaylistOverlayState({
    required this.status,
    required this.videos,
    required this.error,
    required this.isBusy,
    required this.startingTrackId,
  });

  const PlaylistOverlayState.loading()
      : status = PlaylistOverlayStatus.loading,
        videos = const <Video>[],
        error = null,
        isBusy = false,
        startingTrackId = null;

  PlaylistOverlayState copyWith({
    PlaylistOverlayStatus? status,
    List<Video>? videos,
    String? error,
    bool? isBusy,
    String? startingTrackId,
  }) {
    return PlaylistOverlayState(
      status: status ?? this.status,
      videos: videos ?? this.videos,
      error: error,
      isBusy: isBusy ?? this.isBusy,
      startingTrackId: startingTrackId,
    );
  }

  @override
  List<Object?> get props => [status, videos, error, isBusy, startingTrackId];
}

