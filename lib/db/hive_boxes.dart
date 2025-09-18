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

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
    } catch (_) {
      // Hive might already be initialized; ignore
    }
    // Boxes will be lazily opened where needed
  }
}
