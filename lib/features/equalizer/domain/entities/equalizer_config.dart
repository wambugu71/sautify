/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';

import 'equalizer_band.dart';

class EqualizerConfig extends Equatable {
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

  const EqualizerConfig({
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

  @override
  List<Object?> get props => [
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

