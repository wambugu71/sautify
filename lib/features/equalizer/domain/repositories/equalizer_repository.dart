/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import '../entities/equalizer_config.dart';

abstract class EqualizerRepository {
  Future<EqualizerConfig> load();

  Future<void> setEnabled(bool enabled);
  Future<void> setBandGain(int bandIndex, double gainDb);
  Future<void> resetBands();

  Future<void> setSkipSilenceEnabled(bool enabled);

  Future<void> setLoudnessEnhancerEnabled(bool enabled);
  Future<void> setLoudnessEnhancerTargetGain(double gainDb);

  Future<void> setPlaybackSpeed(double speed);
  Future<void> setPitch(double pitch);
}

