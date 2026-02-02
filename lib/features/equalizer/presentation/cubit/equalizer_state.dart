/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';

import '../../domain/entities/equalizer_band.dart';

enum EqualizerStatus { loading, ready, unavailable }

class EqualizerState extends Equatable {
  final EqualizerStatus status;
  final bool isSupported;
  final bool isAvailable;
  final bool enabled;

  final double minDb;
  final double maxDb;
  final List<EqualizerBand> bands;

  final bool skipSilenceEnabled;

  final bool loudnessEnhancerEnabled;
  final double loudnessEnhancerTargetGain;

  final double playbackSpeed;
  final double pitch;

  const EqualizerState({
    required this.status,
    required this.isSupported,
    required this.isAvailable,
    required this.enabled,
    required this.minDb,
    required this.maxDb,
    required this.bands,
    required this.skipSilenceEnabled,
    required this.loudnessEnhancerEnabled,
    required this.loudnessEnhancerTargetGain,
    required this.playbackSpeed,
    required this.pitch,
  });

  const EqualizerState.loading()
      : status = EqualizerStatus.loading,
        isSupported = true,
        isAvailable = false,
        enabled = false,
        minDb = -15.0,
        maxDb = 15.0,
        bands = const <EqualizerBand>[],
        skipSilenceEnabled = false,
        loudnessEnhancerEnabled = false,
        loudnessEnhancerTargetGain = 0.0,
        playbackSpeed = 1.0,
        pitch = 1.0;

  EqualizerState copyWith({
    EqualizerStatus? status,
    bool? isSupported,
    bool? isAvailable,
    bool? enabled,
    double? minDb,
    double? maxDb,
    List<EqualizerBand>? bands,
    bool? skipSilenceEnabled,
    bool? loudnessEnhancerEnabled,
    double? loudnessEnhancerTargetGain,
    double? playbackSpeed,
    double? pitch,
  }) {
    return EqualizerState(
      status: status ?? this.status,
      isSupported: isSupported ?? this.isSupported,
      isAvailable: isAvailable ?? this.isAvailable,
      enabled: enabled ?? this.enabled,
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      bands: bands ?? this.bands,
      skipSilenceEnabled: skipSilenceEnabled ?? this.skipSilenceEnabled,
      loudnessEnhancerEnabled:
          loudnessEnhancerEnabled ?? this.loudnessEnhancerEnabled,
      loudnessEnhancerTargetGain:
          loudnessEnhancerTargetGain ?? this.loudnessEnhancerTargetGain,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      pitch: pitch ?? this.pitch,
    );
  }

  @override
  List<Object?> get props => [
        status,
        isSupported,
        isAvailable,
        enabled,
        minDb,
        maxDb,
        bands,
        skipSilenceEnabled,
        loudnessEnhancerEnabled,
        loudnessEnhancerTargetGain,
        playbackSpeed,
        pitch,
      ];
}

