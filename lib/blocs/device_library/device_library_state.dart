/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class DeviceLibraryState extends Equatable {
  final bool isLoading;
  final bool hasPermission;
  final String? error;
  final List<StreamingData> tracks;

  const DeviceLibraryState({
    this.isLoading = false,
    this.hasPermission = false,
    this.error,
    this.tracks = const [],
  });

  DeviceLibraryState copyWith({
    bool? isLoading,
    bool? hasPermission,
    String? error,
    List<StreamingData>? tracks,
  }) {
    return DeviceLibraryState(
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      error: error,
      tracks: tracks ?? this.tracks,
    );
  }

  @override
  List<Object?> get props => [isLoading, hasPermission, error, tracks];
}

