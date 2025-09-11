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
