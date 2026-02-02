/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sautifyv2/features/equalizer/domain/entities/equalizer_band.dart';
import 'package:sautifyv2/features/equalizer/domain/entities/equalizer_config.dart';
import 'package:sautifyv2/features/equalizer/domain/repositories/equalizer_repository.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

class EqualizerRepositoryImpl implements EqualizerRepository {
  final AudioPlayerService audio;
  final SettingsService settings;

  EqualizerRepositoryImpl({required this.audio, required this.settings});

  @override
  Future<EqualizerConfig> load() async {
    if (!Platform.isAndroid) {
      return const EqualizerConfig(
        isSupported: false,
        isAvailable: false,
        enabled: false,
        minDb: -15.0,
        maxDb: 15.0,
        bands: <EqualizerBand>[],
        skipSilenceEnabled: false,
        loudnessEnhancerEnabled: false,
        loudnessEnhancerTargetGain: 0.0,
        playbackSpeed: 1.0,
        pitch: 1.0,
      );
    }

    if (!settings.isReady) {
      await settings.init();
    }

    try {
      final params = await audio.equalizer.parameters;
      final enabled = settings.equalizerEnabled;

      // Ensure effect state matches settings
      await audio.equalizer.setEnabled(enabled);

      final bands = params.bands.map((b) {
        final gain = settings.equalizerBands[b.index] ?? 0.0;
        return EqualizerBand(
          index: b.index,
          centerFrequencyHz: b.centerFrequency.toInt(),
          gainDb: gain,
        );
      }).toList(growable: false);

      return EqualizerConfig(
        isSupported: true,
        isAvailable: true,
        enabled: enabled,
        minDb: params.minDecibels,
        maxDb: params.maxDecibels,
        bands: bands,
        skipSilenceEnabled: settings.skipSilenceEnabled,
        loudnessEnhancerEnabled: settings.loudnessEnhancerEnabled,
        loudnessEnhancerTargetGain: settings.loudnessEnhancerTargetGain,
        playbackSpeed: settings.defaultPlaybackSpeed,
        pitch: settings.pitch,
      );
    } catch (e) {
      debugPrint('Equalizer not available: $e');
      return EqualizerConfig(
        isSupported: true,
        isAvailable: false,
        enabled: false,
        minDb: -15.0,
        maxDb: 15.0,
        bands: const <EqualizerBand>[],
        skipSilenceEnabled: settings.skipSilenceEnabled,
        loudnessEnhancerEnabled: settings.loudnessEnhancerEnabled,
        loudnessEnhancerTargetGain: settings.loudnessEnhancerTargetGain,
        playbackSpeed: settings.defaultPlaybackSpeed,
        pitch: settings.pitch,
      );
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await settings.setEqualizerEnabled(enabled);
    try {
      await audio.equalizer.setEnabled(enabled);
    } catch (_) {}
  }

  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    try {
      final params = await audio.equalizer.parameters;
      final band = params.bands.firstWhere((b) => b.index == bandIndex);
      final clamped = gainDb.clamp(params.minDecibels, params.maxDecibels);
      await band.setGain(clamped);
      await settings.setEqualizerBand(bandIndex, gainDb);
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> resetBands() async {
    try {
      final params = await audio.equalizer.parameters;
      for (final band in params.bands) {
        await band.setGain(0.0);
        await settings.setEqualizerBand(band.index, 0.0);
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    await settings.setSkipSilenceEnabled(enabled);
    try {
      await audio.player.setSkipSilenceEnabled(enabled);
    } catch (_) {}
  }

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    await settings.setLoudnessEnhancerEnabled(enabled);
    try {
      await audio.loudnessEnhancer.setEnabled(enabled);
    } catch (_) {}
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    await settings.setLoudnessEnhancerTargetGain(gainDb);
    try {
      await audio.loudnessEnhancer.setTargetGain(gainDb);
    } catch (_) {}
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await settings.setDefaultPlaybackSpeed(speed);
    try {
      await audio.player.setSpeed(speed);
    } catch (_) {}
  }

  @override
  Future<void> setPitch(double pitch) async {
    await settings.setPitch(pitch);
    try {
      await audio.player.setPitch(pitch);
    } catch (_) {}
  }
}

