/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sautifyv2/models/streaming_resolver_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  static final SettingsCubit _instance = SettingsCubit._internal();
  factory SettingsCubit() => _instance;
  SettingsCubit._internal() : super(const SettingsState());

  late SharedPreferences _prefs;
  Box<dynamic>? _box;

  // Keys
  static const _kDuckOnInterruption = 'duck_on_interruption';
  static const _kDuckVolume = 'duck_volume';
  static const _kAutoResume = 'auto_resume_after_interruption';
  static const _kCrossfadeSeconds = 'crossfade_seconds';
  static const _kDefaultSpeed = 'default_playback_speed';
  static const _kPitch = 'playback_pitch';
  static const _kDefaultShuffle = 'default_shuffle';
  static const _kDefaultLoopMode = 'default_loop_mode';
  static const _kOfflineMode = 'offline_mode';
  static const _kDefaultVolume = 'default_volume';
  static const _kPreferredQuality = 'preferred_quality';
  static const _kLocaleCode = 'locale_code';
  static const _kDownloadPath = 'download_path';
  static const _kShowRecentSearches = 'show_recent_searches';
  static const _kShowSearchSuggestions = 'show_search_suggestions';
  static const _kEqualizerEnabled = 'equalizer_enabled';
  static const _kEqualizerBands = 'equalizer_bands';
  static const _kLoudnessEnhancerEnabled = 'loudness_enhancer_enabled';
  static const _kLoudnessEnhancerTargetGain = 'loudness_enhancer_target_gain';
  static const _kBassBoostEnabled = 'bass_boost_enabled';
  static const _kBassBoostStrength = 'bass_boost_strength';
  static const _kSkipSilenceEnabled = 'skip_silence_enabled';
  static const _kDynamicThemeEnabled = 'dynamic_theme_enabled';
  static const _kAppFont = 'app_font';
  static const _kStreamingResolverPreference = 'streaming_resolver_preference';

  static const Set<String> _allowedFonts = {
    'system',
    'poppins',
    'inter',
    'roboto',
    'dm_sans',
    'manrope',
    'noto_sans',
  };

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _box = await Hive.openBox('app_prefs');

    final duckOnInterruption =
        _prefs.getBool(_kDuckOnInterruption) ?? state.duckOnInterruption;
    final duckVolume = _prefs.getDouble(_kDuckVolume) ?? state.duckVolume;
    final autoResumeAfterInterruption =
        _prefs.getBool(_kAutoResume) ?? state.autoResumeAfterInterruption;
    final crossfadeSeconds =
        _prefs.getInt(_kCrossfadeSeconds) ?? state.crossfadeSeconds;
    final defaultPlaybackSpeed =
        _prefs.getDouble(_kDefaultSpeed) ?? state.defaultPlaybackSpeed;
    final pitch = _prefs.getDouble(_kPitch) ?? state.pitch;
    final defaultShuffle =
        _prefs.getBool(_kDefaultShuffle) ?? state.defaultShuffle;
    final defaultLoopMode =
        _prefs.getString(_kDefaultLoopMode) ?? state.defaultLoopMode;
    final offlineMode = _prefs.getBool(_kOfflineMode) ?? state.offlineMode;
    final defaultVolume =
        _prefs.getDouble(_kDefaultVolume) ?? state.defaultVolume;
    final preferredQuality =
        _prefs.getString(_kPreferredQuality) ?? state.preferredQuality;
    var downloadPath = _prefs.getString(_kDownloadPath) ?? state.downloadPath;
    final hasStoredDownloadPath = _prefs.containsKey(_kDownloadPath);

    // Default download directory.
    // Android: user-requested Music folder.
    // iOS: app documents directory.
    if (!hasStoredDownloadPath || downloadPath.isEmpty) {
      if (Platform.isAndroid) {
        final dir = Directory('/storage/emulated/0/Music');
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          downloadPath = dir.path;
          await _prefs.setString(_kDownloadPath, downloadPath);
        } catch (_) {
          // Fallback to app-writable directory.
          final Directory baseDir = (await getExternalStorageDirectory()) ??
              await getApplicationDocumentsDirectory();
          final fallback = Directory(
            '${baseDir.path}${Platform.pathSeparator}Sautify${Platform.pathSeparator}Downloads',
          );
          try {
            if (!await fallback.exists()) {
              await fallback.create(recursive: true);
            }
            downloadPath = fallback.path;
            await _prefs.setString(_kDownloadPath, downloadPath);
          } catch (_) {
            // If we can't create the dir, keep the stored/default path.
          }
        }
      } else if (Platform.isIOS) {
        final Directory baseDir = await getApplicationDocumentsDirectory();
        final dir = Directory(
          '${baseDir.path}${Platform.pathSeparator}Sautify${Platform.pathSeparator}Downloads',
        );
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          downloadPath = dir.path;
          await _prefs.setString(_kDownloadPath, downloadPath);
        } catch (_) {
          // If we can't create the dir, keep the stored/default path.
        }
      }
    }

    final hiveLocale = _box?.get(_kLocaleCode) as String?;
    final localeCode =
        hiveLocale ?? _prefs.getString(_kLocaleCode) ?? state.localeCode;

    final showRecentSearches =
        (_box?.get(_kShowRecentSearches) as bool?) ?? state.showRecentSearches;
    final showSearchSuggestions =
        (_box?.get(_kShowSearchSuggestions) as bool?) ??
            state.showSearchSuggestions;

    final equalizerEnabled =
        _prefs.getBool(_kEqualizerEnabled) ?? state.equalizerEnabled;
    final loudnessEnhancerEnabled = _prefs.getBool(_kLoudnessEnhancerEnabled) ??
        state.loudnessEnhancerEnabled;
    final loudnessEnhancerTargetGain =
        _prefs.getDouble(_kLoudnessEnhancerTargetGain) ??
            state.loudnessEnhancerTargetGain;
    final bassBoostEnabled =
        _prefs.getBool(_kBassBoostEnabled) ?? state.bassBoostEnabled;
    final bassBoostStrength =
        _prefs.getInt(_kBassBoostStrength) ?? state.bassBoostStrength;
    final skipSilenceEnabled =
        _prefs.getBool(_kSkipSilenceEnabled) ?? state.skipSilenceEnabled;
    final dynamicThemeEnabled =
        _prefs.getBool(_kDynamicThemeEnabled) ?? state.dynamicThemeEnabled;

    final appFont = _prefs.getString(_kAppFont) ?? state.appFont;
    final resolvedAppFont =
        _allowedFonts.contains(appFont) ? appFont : 'poppins';

    final streamingResolverPreference =
        StreamingResolverPreferencePrefs.fromPrefValue(
      _prefs.getString(_kStreamingResolverPreference),
    );

    Map<int, double> equalizerBands = {};
    final loadedBands = _prefs.getString(_kEqualizerBands);
    if (loadedBands != null) {
      try {
        final List<String> pairs = loadedBands.split(',');
        for (var pair in pairs) {
          final indexGain = pair.split(':');
          if (indexGain.length == 2) {
            final index = int.tryParse(indexGain[0]);
            final gain = double.tryParse(indexGain[1]);
            if (index != null && gain != null) {
              equalizerBands[index] = gain;
            }
          }
        }
      } catch (e) {}
    }

    emit(state.copyWith(
      duckOnInterruption: duckOnInterruption,
      duckVolume: duckVolume,
      autoResumeAfterInterruption: autoResumeAfterInterruption,
      crossfadeSeconds: crossfadeSeconds,
      defaultPlaybackSpeed: defaultPlaybackSpeed,
      pitch: pitch,
      defaultShuffle: defaultShuffle,
      defaultLoopMode: defaultLoopMode,
      offlineMode: offlineMode,
      defaultVolume: defaultVolume,
      preferredQuality: preferredQuality,
      localeCode: localeCode,
      downloadPath: downloadPath,
      showRecentSearches: showRecentSearches,
      showSearchSuggestions: showSearchSuggestions,
      equalizerEnabled: equalizerEnabled,
      equalizerBands: equalizerBands,
      loudnessEnhancerEnabled: loudnessEnhancerEnabled,
      loudnessEnhancerTargetGain: loudnessEnhancerTargetGain,
      bassBoostEnabled: bassBoostEnabled,
      bassBoostStrength: bassBoostStrength,
      skipSilenceEnabled: skipSilenceEnabled,
      dynamicThemeEnabled: dynamicThemeEnabled,
      appFont: resolvedAppFont,
      streamingResolverPreference: streamingResolverPreference,
      isReady: true,
    ));
  }

  Future<void> setStreamingResolverPreference(
    StreamingResolverPreference value,
  ) async {
    await _prefs.setString(_kStreamingResolverPreference, value.prefValue);
    emit(state.copyWith(streamingResolverPreference: value));
  }

  Future<void> setAppFont(String value) async {
    final v = value.trim();
    if (!_allowedFonts.contains(v)) return;
    await _prefs.setString(_kAppFont, v);
    emit(state.copyWith(appFont: v));
  }

  Future<void> setDuckOnInterruption(bool value) async {
    await _prefs.setBool(_kDuckOnInterruption, value);
    emit(state.copyWith(duckOnInterruption: value));
  }

  Future<void> setDuckVolume(double value) async {
    final val = value.clamp(0.0, 1.0);
    await _prefs.setDouble(_kDuckVolume, val);
    emit(state.copyWith(duckVolume: val));
  }

  Future<void> setAutoResumeAfterInterruption(bool value) async {
    await _prefs.setBool(_kAutoResume, value);
    emit(state.copyWith(autoResumeAfterInterruption: value));
  }

  Future<void> setCrossfadeSeconds(int value) async {
    final val = value.clamp(0, 12);
    await _prefs.setInt(_kCrossfadeSeconds, val);
    emit(state.copyWith(crossfadeSeconds: val));
  }

  Future<void> setDefaultPlaybackSpeed(double value) async {
    final val = double.parse(value.toStringAsFixed(2));
    await _prefs.setDouble(_kDefaultSpeed, val);
    emit(state.copyWith(defaultPlaybackSpeed: val));
  }

  Future<void> setPitch(double value) async {
    final val = double.parse(value.toStringAsFixed(2));
    await _prefs.setDouble(_kPitch, val);
    emit(state.copyWith(pitch: val));
  }

  Future<void> setDefaultShuffle(bool value) async {
    await _prefs.setBool(_kDefaultShuffle, value);
    emit(state.copyWith(defaultShuffle: value));
  }

  Future<void> setDefaultLoopMode(String value) async {
    await _prefs.setString(_kDefaultLoopMode, value);
    emit(state.copyWith(defaultLoopMode: value));
  }

  Future<void> setOfflineMode(bool value) async {
    await _prefs.setBool(_kOfflineMode, value);
    emit(state.copyWith(offlineMode: value));
  }

  Future<void> setDefaultVolume(double value) async {
    final val = value.clamp(0.0, 1.0);
    await _prefs.setDouble(_kDefaultVolume, val);
    emit(state.copyWith(defaultVolume: val));
  }

  Future<void> setPreferredQuality(String value) async {
    if (!['low', 'medium', 'high'].contains(value)) return;
    await _prefs.setString(_kPreferredQuality, value);
    emit(state.copyWith(preferredQuality: value));
  }

  Future<void> setLocaleCode(String code) async {
    await _box?.put(_kLocaleCode, code);
    await _prefs.setString(_kLocaleCode, code);
    emit(state.copyWith(localeCode: code));
  }

  Future<void> setDownloadPath(String path) async {
    await _prefs.setString(_kDownloadPath, path);
    emit(state.copyWith(downloadPath: path));
  }

  Future<void> setShowRecentSearches(bool value) async {
    await _box?.put(_kShowRecentSearches, value);
    emit(state.copyWith(showRecentSearches: value));
  }

  Future<void> setShowSearchSuggestions(bool value) async {
    await _box?.put(_kShowSearchSuggestions, value);
    emit(state.copyWith(showSearchSuggestions: value));
  }

  Future<void> setEqualizerEnabled(bool value) async {
    await _prefs.setBool(_kEqualizerEnabled, value);
    emit(state.copyWith(equalizerEnabled: value));
  }

  Future<void> setEqualizerBand(int index, double gain) async {
    final newBands = Map<int, double>.from(state.equalizerBands);
    newBands[index] = gain;
    final String serialized =
        newBands.entries.map((e) => '${e.key}:${e.value}').join(',');
    await _prefs.setString(_kEqualizerBands, serialized);
    emit(state.copyWith(equalizerBands: newBands));
  }

  Future<void> setLoudnessEnhancerEnabled(bool value) async {
    await _prefs.setBool(_kLoudnessEnhancerEnabled, value);
    emit(state.copyWith(loudnessEnhancerEnabled: value));
  }

  Future<void> setLoudnessEnhancerTargetGain(double value) async {
    await _prefs.setDouble(_kLoudnessEnhancerTargetGain, value);
    emit(state.copyWith(loudnessEnhancerTargetGain: value));
  }

  Future<void> setBassBoostEnabled(bool value) async {
    await _prefs.setBool(_kBassBoostEnabled, value);
    emit(state.copyWith(bassBoostEnabled: value));
  }

  Future<void> setBassBoostStrength(int value) async {
    await _prefs.setInt(_kBassBoostStrength, value);
    emit(state.copyWith(bassBoostStrength: value));
  }

  Future<void> setSkipSilenceEnabled(bool value) async {
    await _prefs.setBool(_kSkipSilenceEnabled, value);
    emit(state.copyWith(skipSilenceEnabled: value));
  }

  Future<void> setDynamicThemeEnabled(bool value) async {
    await _prefs.setBool(_kDynamicThemeEnabled, value);
    emit(state.copyWith(dynamicThemeEnabled: value));
  }

  Future<void> resetToDefaults() async {
    const newState = SettingsState(isReady: true);

    await _prefs.setBool(_kDuckOnInterruption, newState.duckOnInterruption);
    await _prefs.setDouble(_kDuckVolume, newState.duckVolume);
    await _prefs.setBool(_kAutoResume, newState.autoResumeAfterInterruption);
    await _prefs.setInt(_kCrossfadeSeconds, newState.crossfadeSeconds);
    await _prefs.setDouble(_kDefaultSpeed, newState.defaultPlaybackSpeed);
    await _prefs.setDouble(_kPitch, newState.pitch);
    await _prefs.setBool(_kDefaultShuffle, newState.defaultShuffle);
    await _prefs.setString(_kDefaultLoopMode, newState.defaultLoopMode);
    await _prefs.setDouble(_kDefaultVolume, newState.defaultVolume);
    await _prefs.setString(_kPreferredQuality, newState.preferredQuality);
    await _box?.put(_kLocaleCode, newState.localeCode);
    await _box?.put(_kShowRecentSearches, newState.showRecentSearches);
    await _box?.put(_kShowSearchSuggestions, newState.showSearchSuggestions);
    await _prefs.setString(_kLocaleCode, newState.localeCode);
    await _prefs.setBool(_kEqualizerEnabled, newState.equalizerEnabled);
    await _prefs.setString(_kEqualizerBands, '');
    await _prefs.setBool(
        _kLoudnessEnhancerEnabled, newState.loudnessEnhancerEnabled);
    await _prefs.setDouble(
        _kLoudnessEnhancerTargetGain, newState.loudnessEnhancerTargetGain);
    await _prefs.setBool(_kBassBoostEnabled, newState.bassBoostEnabled);
    await _prefs.setInt(_kBassBoostStrength, newState.bassBoostStrength);
    await _prefs.setBool(_kSkipSilenceEnabled, newState.skipSilenceEnabled);
    await _prefs.setBool(_kDynamicThemeEnabled, newState.dynamicThemeEnabled);
    await _prefs.setString(
      _kStreamingResolverPreference,
      newState.streamingResolverPreference.prefValue,
    );

    emit(newState);
  }
}

