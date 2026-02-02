/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/equalizer_repository.dart';
import 'equalizer_state.dart';

class EqualizerCubit extends Cubit<EqualizerState> {
  final EqualizerRepository repo;

  EqualizerCubit({required this.repo}) : super(const EqualizerState.loading());

  Future<void> init() async {
    emit(const EqualizerState.loading());
    final config = await repo.load();

    if (!config.isSupported) {
      emit(state.copyWith(
        status: EqualizerStatus.unavailable,
        isSupported: false,
        isAvailable: false,
      ));
      return;
    }

    if (!config.isAvailable) {
      emit(state.copyWith(
        status: EqualizerStatus.unavailable,
        isSupported: true,
        isAvailable: false,
      ));
      return;
    }

    emit(state.copyWith(
      status: EqualizerStatus.ready,
      isSupported: true,
      isAvailable: true,
      enabled: config.enabled,
      minDb: config.minDb,
      maxDb: config.maxDb,
      bands: config.bands,
      skipSilenceEnabled: config.skipSilenceEnabled,
      loudnessEnhancerEnabled: config.loudnessEnhancerEnabled,
      loudnessEnhancerTargetGain: config.loudnessEnhancerTargetGain,
      playbackSpeed: config.playbackSpeed,
      pitch: config.pitch,
    ));
  }

  Future<void> setEnabled(bool enabled) async {
    emit(state.copyWith(enabled: enabled));
    await repo.setEnabled(enabled);
  }

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    final updated = state.bands
        .map((b) => b.index == bandIndex ? b.copyWith(gainDb: gainDb) : b)
        .toList(growable: false);
    emit(state.copyWith(bands: updated));
    await repo.setBandGain(bandIndex, gainDb);
  }

  Future<void> resetBands() async {
    final updated =
        state.bands.map((b) => b.copyWith(gainDb: 0.0)).toList(growable: false);
    emit(state.copyWith(bands: updated));
    await repo.resetBands();
  }

  Future<void> setSkipSilenceEnabled(bool enabled) async {
    emit(state.copyWith(skipSilenceEnabled: enabled));
    await repo.setSkipSilenceEnabled(enabled);
  }

  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    emit(state.copyWith(loudnessEnhancerEnabled: enabled));
    await repo.setLoudnessEnhancerEnabled(enabled);
  }

  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    emit(state.copyWith(loudnessEnhancerTargetGain: gainDb));
    await repo.setLoudnessEnhancerTargetGain(gainDb);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    emit(state.copyWith(playbackSpeed: speed));
    await repo.setPlaybackSpeed(speed);
  }

  Future<void> setPitch(double pitch) async {
    emit(state.copyWith(pitch: pitch));
    await repo.setPitch(pitch);
  }
}

