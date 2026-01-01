/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  static const String favorites = 'favorites_box';
  static const String recentPlays = 'recent_plays_box';
  static const String playlists = 'playlists_box';
  static const String albums = 'albums_box';
  static const String stats = 'stats_box';
  static const String continueListening = 'continue_listening_box';
  static const String metadataOverrides = 'metadata_overrides_box';

  static Future<void>? _initFuture;

  static Future<void> init() async {
    final existing = _initFuture;
    if (existing != null) return existing;

    final fut = () async {
      try {
        await Hive.initFlutter();
      } catch (_) {
        // Hive might already be initialized; ignore
      }
    }();

    _initFuture = fut;
    return fut;
  }
}
