/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/db/hive_boxes.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class LibraryStore {
  static Future<Box<String>> _openBox(String name) async {
    // Ensure Hive initialized
    await HiveBoxes.init();
    return Hive.isBoxOpen(name)
        ? Hive.box<String>(name)
        : await Hive.openBox<String>(name);
  }

  // Recents
  static Future<void> addRecent(StreamingData track) async {
    final box = await _openBox(HiveBoxes.recentPlays);
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, jsonEncode(track.toJson()));
    if (box.length > 100) {
      await box.deleteAt(0);
    }
  }

  // Favorites
  static Future<void> toggleFavorite(StreamingData track) async {
    final box = await _openBox(HiveBoxes.favorites);
    final key = track.videoId;
    if (box.containsKey(key)) {
      await box.delete(key);
    } else {
      await box.put(key, jsonEncode(track.toJson()));
    }
  }

  static Future<bool> isFavorite(String videoId) async {
    final box = await _openBox(HiveBoxes.favorites);
    return box.containsKey(videoId);
  }

  // Playlists
  static Future<void> savePlaylist(SavedPlaylist playlist) async {
    final box = await _openBox(HiveBoxes.playlists);
    await box.put(playlist.id, jsonEncode(playlist.toJson()));
  }

  // Albums
  static Future<void> saveAlbum(SavedAlbum album) async {
    final box = await _openBox(HiveBoxes.albums);
    await box.put(album.id, jsonEncode(album.toJson()));
  }
}
