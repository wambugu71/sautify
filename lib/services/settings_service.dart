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
  // Search-related keys (Hive-backed)
  static const _kShowRecentSearches = 'show_recent_searches';
  static const _kShowSearchSuggestions = 'show_search_suggestions';

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
  // Search-related defaults (OFF as requested)
  bool showRecentSearches = false;
  bool showSearchSuggestions = false;

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
    // Prefer Hive for locale (requested), fallback to SharedPreferences
    final hiveLocale = _box?.get(_kLocaleCode) as String?;
    localeCode = hiveLocale ?? _prefs.getString(_kLocaleCode) ?? localeCode;
    // Load search-related flags from Hive only (source of truth)
    showRecentSearches =
        (_box?.get(_kShowRecentSearches) as bool?) ?? showRecentSearches;
    showSearchSuggestions =
        (_box?.get(_kShowSearchSuggestions) as bool?) ?? showSearchSuggestions;
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

    notifyListeners();
  }
}
