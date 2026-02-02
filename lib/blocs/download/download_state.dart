/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class DownloadState extends Equatable {
  final Set<String> downloadingIds;
  final List<StreamingData> downloadedTracks;
  final bool hasPermission;
  final bool isLoading;
  final bool isInitialized;
  final int? eventId;
  final String? eventVideoId;
  final String? eventMessage;
  final bool eventIsError;

  final String? activeDownloadVideoId;
  final int progressReceived;
  final int progressTotal;

  const DownloadState({
    this.downloadingIds = const {},
    this.downloadedTracks = const [],
    this.hasPermission = false,
    this.isLoading = false,
    this.isInitialized = false,
    this.eventId = 0,
    this.eventVideoId,
    this.eventMessage,
    this.eventIsError = false,
    this.activeDownloadVideoId,
    this.progressReceived = 0,
    this.progressTotal = 0,
  });

  DownloadState copyWith({
    Set<String>? downloadingIds,
    List<StreamingData>? downloadedTracks,
    bool? hasPermission,
    bool? isLoading,
    bool? isInitialized,
    int? eventId,
    String? eventVideoId,
    String? eventMessage,
    bool? eventIsError,
    String? activeDownloadVideoId,
    int? progressReceived,
    int? progressTotal,
  }) {
    return DownloadState(
      downloadingIds: downloadingIds ?? this.downloadingIds,
      downloadedTracks: downloadedTracks ?? this.downloadedTracks,
      hasPermission: hasPermission ?? this.hasPermission,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      eventId: eventId ?? (this.eventId ?? 0),
      eventVideoId: eventVideoId,
      eventMessage: eventMessage,
      eventIsError: eventIsError ?? this.eventIsError,
      activeDownloadVideoId:
          activeDownloadVideoId ?? this.activeDownloadVideoId,
      progressReceived: progressReceived ?? this.progressReceived,
      progressTotal: progressTotal ?? this.progressTotal,
    );
  }

  double? get progressRatio {
    if (progressTotal <= 0) return null;
    return (progressReceived / progressTotal).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
        downloadingIds,
        downloadedTracks,
        hasPermission,
        isLoading,
        isInitialized,
        eventId,
        eventVideoId,
        eventMessage,
        eventIsError,
        activeDownloadVideoId,
        progressReceived,
        progressTotal,
      ];
}

