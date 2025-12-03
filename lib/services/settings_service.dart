/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  Box<dynamic>? _box; // Hive box for select settings (e.g., locale)
  bool _ready = false;

  // Keys
  static const _kDuckOnInterruption = 'duck_on_interruption';
  static const _kDuckVolume = 'duck_volume';
  static const _kAutoResume = 'auto_resume_after_interruption';
  static const _kCrossfadeSeconds = 'crossfade_seconds';
  static const _kDefaultSpeed = 'default_playback_speed';
  static const _kDefaultShuffle = 'default_shuffle';
  static const _kDefaultLoopMode = 'default_loop_mode'; // off | one | all
  // New keys
  static const _kDefaultVolume = 'default_volume'; // 0.0 - 1.0
  static const _kPreferredQuality = 'preferred_quality'; // low | medium | high
  static const _kLocaleCode = 'locale_code'; // e.g., en, sw, sw-KE
  static const _kDownloadPath = 'download_path';
  // Search-related keys (Hive-backed)
  static const _kShowRecentSearches = 'show_recent_searches';
  static const _kShowSearchSuggestions = 'show_search_suggestions';
  // Equalizer settings keys
  static const _kEqualizerEnabled = 'equalizer_enabled';
  static const _kEqualizerBands = 'equalizer_bands'; // index:gain,index:gain

  // Defaults
  bool duckOnInterruption = true;
  double duckVolume = 0.5; // 0.0 - 1.0
  bool autoResumeAfterInterruption = true;
  int crossfadeSeconds = 0; // 0 - 12
  double defaultPlaybackSpeed = 1.0; // 0.5 - 2.0
  bool defaultShuffle = false;
  String defaultLoopMode = 'off';
  // New defaults
  double defaultVolume = 1.0; // 0.0 - 1.0
  String preferredQuality = 'medium'; // low | medium | high
  String localeCode = 'en'; // default English
  String downloadPath =
      '/storage/emulated/0/Music'; // Default Android Music folder
  // Search-related defaults (OFF as requested)
  bool showRecentSearches = false;
  bool showSearchSuggestions = false;
  // Equalizer settings defaults
  bool equalizerEnabled = false;
  Map<int, double> equalizerBands = {};

  bool get isReady => _ready;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _box = await Hive.openBox('app_prefs');
    duckOnInterruption =
        _prefs.getBool(_kDuckOnInterruption) ?? duckOnInterruption;
    duckVolume = _prefs.getDouble(_kDuckVolume) ?? duckVolume;
    autoResumeAfterInterruption =
        _prefs.getBool(_kAutoResume) ?? autoResumeAfterInterruption;
    crossfadeSeconds = _prefs.getInt(_kCrossfadeSeconds) ?? crossfadeSeconds;
    defaultPlaybackSpeed =
        _prefs.getDouble(_kDefaultSpeed) ?? defaultPlaybackSpeed;
    defaultShuffle = _prefs.getBool(_kDefaultShuffle) ?? defaultShuffle;
    defaultLoopMode = _prefs.getString(_kDefaultLoopMode) ?? defaultLoopMode;
    // New loads
    defaultVolume = _prefs.getDouble(_kDefaultVolume) ?? defaultVolume;
    preferredQuality = _prefs.getString(_kPreferredQuality) ?? preferredQuality;
    downloadPath = _prefs.getString(_kDownloadPath) ?? downloadPath;
    // Prefer Hive for locale (requested), fallback to SharedPreferences
    final hiveLocale = _box?.get(_kLocaleCode) as String?;
    localeCode = hiveLocale ?? _prefs.getString(_kLocaleCode) ?? localeCode;
    // Load search-related flags from Hive only (source of truth)
    showRecentSearches =
        (_box?.get(_kShowRecentSearches) as bool?) ?? showRecentSearches;
    showSearchSuggestions =
        (_box?.get(_kShowSearchSuggestions) as bool?) ?? showSearchSuggestions;
    // Load equalizer settings
    equalizerEnabled = (_prefs.getBool(_kEqualizerEnabled) ?? equalizerEnabled);
    final loadedBands = _prefs.getString(_kEqualizerBands);
    if (loadedBands != null) {
      try {
        final List<String> pairs = loadedBands.split(',');
        final Map<int, double> bandsMap = {};
        for (var pair in pairs) {
          final indexGain = pair.split(':');
          if (indexGain.length == 2) {
            final index = int.tryParse(indexGain[0]);
            final gain = double.tryParse(indexGain[1]);
            if (index != null && gain != null) {
              bandsMap[index] = gain;
            }
          }
        }
        equalizerBands = bandsMap;
      } catch (e) {
        // Handle potential format errors silently
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> setDuckOnInterruption(bool value) async {
    duckOnInterruption = value;
    await _prefs.setBool(_kDuckOnInterruption, value);
    notifyListeners();
  }

  Future<void> setDuckVolume(double value) async {
    duckVolume = value.clamp(0.0, 1.0);
    await _prefs.setDouble(_kDuckVolume, duckVolume);
    notifyListeners();
  }

  Future<void> setAutoResumeAfterInterruption(bool value) async {
    autoResumeAfterInterruption = value;
    await _prefs.setBool(_kAutoResume, value);
    notifyListeners();
  }

  Future<void> setCrossfadeSeconds(int value) async {
    crossfadeSeconds = value.clamp(0, 12);
    await _prefs.setInt(_kCrossfadeSeconds, crossfadeSeconds);
    notifyListeners();
  }

  Future<void> setDefaultPlaybackSpeed(double value) async {
    defaultPlaybackSpeed = double.parse(value.toStringAsFixed(2));
    await _prefs.setDouble(_kDefaultSpeed, defaultPlaybackSpeed);
    notifyListeners();
  }

  Future<void> setDefaultShuffle(bool value) async {
    defaultShuffle = value;
    await _prefs.setBool(_kDefaultShuffle, defaultShuffle);
    notifyListeners();
  }

  Future<void> setDefaultLoopMode(String value) async {
    if (!['off', 'one', 'all'].contains(value)) return;
    defaultLoopMode = value;
    await _prefs.setString(_kDefaultLoopMode, defaultLoopMode);
    notifyListeners();
  }

  // New setters
  Future<void> setDefaultVolume(double value) async {
    defaultVolume = value.clamp(0.0, 1.0);
    await _prefs.setDouble(_kDefaultVolume, defaultVolume);
    notifyListeners();
  }

  Future<void> setPreferredQuality(String value) async {
    if (!['low', 'medium', 'high'].contains(value)) return;
    preferredQuality = value;
    await _prefs.setString(_kPreferredQuality, preferredQuality);
    notifyListeners();
  }

  Future<void> setLocaleCode(String code) async {
    localeCode = code;
    // Write to Hive as source-of-truth, keep SharedPreferences for compatibility
    await _box?.put(_kLocaleCode, localeCode);
    await _prefs.setString(_kLocaleCode, localeCode);
    notifyListeners();
  }

  Future<void> setDownloadPath(String path) async {
    downloadPath = path;
    await _prefs.setString(_kDownloadPath, path);
    notifyListeners();
  }

  // Search-related setters (Hive-backed)
  Future<void> setShowRecentSearches(bool value) async {
    showRecentSearches = value;
    await _box?.put(_kShowRecentSearches, showRecentSearches);
    notifyListeners();
  }

  Future<void> setShowSearchSuggestions(bool value) async {
    showSearchSuggestions = value;
    await _box?.put(_kShowSearchSuggestions, showSearchSuggestions);
    notifyListeners();
  }

  // Equalizer settings setters
  Future<void> setEqualizerEnabled(bool value) async {
    equalizerEnabled = value;
    await _prefs.setBool(_kEqualizerEnabled, value);
    notifyListeners();
  }

  Future<void> setEqualizerBand(int index, double gain) async {
    equalizerBands[index] = gain;
    // Serialize map to string "index:gain,index:gain"
    final String serialized = equalizerBands.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    await _prefs.setString(_kEqualizerBands, serialized);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    duckOnInterruption = true;
    duckVolume = 0.5;
    autoResumeAfterInterruption = true;
    crossfadeSeconds = 0;
    defaultPlaybackSpeed = 1.0;
    defaultShuffle = false;
    defaultLoopMode = 'off';
    defaultVolume = 1.0;
    preferredQuality = 'medium';
    localeCode = 'en';
    showRecentSearches = false;
    showSearchSuggestions = false;
    equalizerEnabled = false;
    equalizerBands = {};

    await _prefs.setBool(_kDuckOnInterruption, duckOnInterruption);
    await _prefs.setDouble(_kDuckVolume, duckVolume);
    await _prefs.setBool(_kAutoResume, autoResumeAfterInterruption);
    await _prefs.setInt(_kCrossfadeSeconds, crossfadeSeconds);
    await _prefs.setDouble(_kDefaultSpeed, defaultPlaybackSpeed);
    await _prefs.setBool(_kDefaultShuffle, defaultShuffle);
    await _prefs.setString(_kDefaultLoopMode, defaultLoopMode);
    await _prefs.setDouble(_kDefaultVolume, defaultVolume);
    await _prefs.setString(_kPreferredQuality, preferredQuality);
    await _box?.put(_kLocaleCode, localeCode);
    await _box?.put(_kShowRecentSearches, showRecentSearches);
    await _box?.put(_kShowSearchSuggestions, showSearchSuggestions);
    await _prefs.setString(_kLocaleCode, localeCode);
    await _prefs.setBool(_kEqualizerEnabled, equalizerEnabled);
    await _prefs.setString(_kEqualizerBands, '');

    notifyListeners();
  }
}
