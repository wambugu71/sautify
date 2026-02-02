/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/streaming_resolver_preference.dart';

class SettingsState extends Equatable {
  final bool duckOnInterruption;
  final double duckVolume;
  final bool autoResumeAfterInterruption;
  final int crossfadeSeconds;
  final double defaultPlaybackSpeed;
  final double pitch;
  final bool defaultShuffle;
  final String defaultLoopMode;
  final bool offlineMode;
  final double defaultVolume;
  final String preferredQuality;
  final String localeCode;
  final String downloadPath;
  final bool showRecentSearches;
  final bool showSearchSuggestions;
  final bool equalizerEnabled;
  final Map<int, double> equalizerBands;
  final bool loudnessEnhancerEnabled;
  final double loudnessEnhancerTargetGain;
  final bool bassBoostEnabled;
  final int bassBoostStrength;
  final bool skipSilenceEnabled;
  final bool dynamicThemeEnabled;
  final String appFont;
  final StreamingResolverPreference streamingResolverPreference;
  final bool isReady;

  const SettingsState({
    this.duckOnInterruption = true,
    this.duckVolume = 0.5,
    this.autoResumeAfterInterruption = true,
    this.crossfadeSeconds = 0,
    this.defaultPlaybackSpeed = 1.0,
    this.pitch = 1.0,
    this.defaultShuffle = false,
    this.defaultLoopMode = 'off',
    this.offlineMode = false,
    this.defaultVolume = 1.0,
    this.preferredQuality = 'medium',
    this.localeCode = 'en',
    this.downloadPath = '/storage/emulated/0/Music',
    this.showRecentSearches = false,
    this.showSearchSuggestions = false,
    this.equalizerEnabled = false,
    this.equalizerBands = const {},
    this.loudnessEnhancerEnabled = false,
    this.loudnessEnhancerTargetGain = 0.0,
    this.bassBoostEnabled = false,
    this.bassBoostStrength = 0,
    this.skipSilenceEnabled = false,
    this.dynamicThemeEnabled = false,
    this.appFont = 'poppins',
    this.streamingResolverPreference = StreamingResolverPreference.defaultMode,
    this.isReady = false,
  });

  SettingsState copyWith({
    bool? duckOnInterruption,
    double? duckVolume,
    bool? autoResumeAfterInterruption,
    int? crossfadeSeconds,
    double? defaultPlaybackSpeed,
    double? pitch,
    bool? defaultShuffle,
    String? defaultLoopMode,
    bool? offlineMode,
    double? defaultVolume,
    String? preferredQuality,
    String? localeCode,
    String? downloadPath,
    bool? showRecentSearches,
    bool? showSearchSuggestions,
    bool? equalizerEnabled,
    Map<int, double>? equalizerBands,
    bool? loudnessEnhancerEnabled,
    double? loudnessEnhancerTargetGain,
    bool? bassBoostEnabled,
    int? bassBoostStrength,
    bool? skipSilenceEnabled,
    bool? dynamicThemeEnabled,
    String? appFont,
    StreamingResolverPreference? streamingResolverPreference,
    bool? isReady,
  }) {
    return SettingsState(
      duckOnInterruption: duckOnInterruption ?? this.duckOnInterruption,
      duckVolume: duckVolume ?? this.duckVolume,
      autoResumeAfterInterruption:
          autoResumeAfterInterruption ?? this.autoResumeAfterInterruption,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      pitch: pitch ?? this.pitch,
      defaultShuffle: defaultShuffle ?? this.defaultShuffle,
      defaultLoopMode: defaultLoopMode ?? this.defaultLoopMode,
      offlineMode: offlineMode ?? this.offlineMode,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      localeCode: localeCode ?? this.localeCode,
      downloadPath: downloadPath ?? this.downloadPath,
      showRecentSearches: showRecentSearches ?? this.showRecentSearches,
      showSearchSuggestions:
          showSearchSuggestions ?? this.showSearchSuggestions,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerBands: equalizerBands ?? this.equalizerBands,
      loudnessEnhancerEnabled:
          loudnessEnhancerEnabled ?? this.loudnessEnhancerEnabled,
      loudnessEnhancerTargetGain:
          loudnessEnhancerTargetGain ?? this.loudnessEnhancerTargetGain,
      bassBoostEnabled: bassBoostEnabled ?? this.bassBoostEnabled,
      bassBoostStrength: bassBoostStrength ?? this.bassBoostStrength,
      skipSilenceEnabled: skipSilenceEnabled ?? this.skipSilenceEnabled,
      dynamicThemeEnabled: dynamicThemeEnabled ?? this.dynamicThemeEnabled,
      appFont: appFont ?? this.appFont,
      streamingResolverPreference:
          streamingResolverPreference ?? this.streamingResolverPreference,
      isReady: isReady ?? this.isReady,
    );
  }

  @override
  List<Object?> get props => [
        duckOnInterruption,
        duckVolume,
        autoResumeAfterInterruption,
        crossfadeSeconds,
        defaultPlaybackSpeed,
        pitch,
        defaultShuffle,
        defaultLoopMode,
        offlineMode,
        defaultVolume,
        preferredQuality,
        localeCode,
        downloadPath,
        showRecentSearches,
        showSearchSuggestions,
        equalizerEnabled,
        equalizerBands,
        loudnessEnhancerEnabled,
        loudnessEnhancerTargetGain,
        bassBoostEnabled,
        bassBoostStrength,
        skipSilenceEnabled,
        dynamicThemeEnabled,
        appFont,
        streamingResolverPreference,
        isReady,
      ];
}

