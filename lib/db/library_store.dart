/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/db/hive_boxes.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/stats_model.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class LibraryStore {
  static final Map<String, Future<Box<String>>> _boxFutures =
      <String, Future<Box<String>>>{};

  static Future<Box<String>> _openBox(String name) async {
    return _boxFutures[name] ??= () async {
      await HiveBoxes.init();
      if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
      return Hive.openBox<String>(name);
    }();
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

  // Stats
  static Future<void> incrementPlayCount(StreamingData track) async {
    final box = await _openBox(HiveBoxes.stats);
    final key = track.videoId;
    SongStats stats;
    if (box.containsKey(key)) {
      final json = jsonDecode(box.get(key)!);
      stats = SongStats.fromJson(json);
      stats.playCount++;
      stats.lastPlayed = DateTime.now();
    } else {
      stats = SongStats(
        videoId: track.videoId,
        title: track.title,
        artist: track.artist,
        thumbnailUrl: track.thumbnailUrl,
        playCount: 1,
        lastPlayed: DateTime.now(),
      );
    }
    await box.put(key, jsonEncode(stats.toJson()));
  }

  static Future<List<SongStats>> getMostPlayed({int limit = 20}) async {
    final box = await _openBox(HiveBoxes.stats);
    final allStats =
        box.values.map((e) => SongStats.fromJson(jsonDecode(e))).toList();
    allStats.sort((a, b) => b.playCount.compareTo(a.playCount));
    return allStats.take(limit).toList();
  }

  static Future<List<StreamingData>> getRecentPlays({int limit = 50}) async {
    final box = await _openBox(HiveBoxes.recentPlays);
    final keys = box.keys.toList();
    // Sort keys descending (newest first) - assuming keys are timestamps as strings
    keys.sort((a, b) => b.toString().compareTo(a.toString()));

    final recentKeys = keys.take(limit);
    final List<StreamingData> list = [];
    for (final key in recentKeys) {
      final jsonStr = box.get(key);
      if (jsonStr != null) {
        list.add(StreamingData.fromJson(jsonDecode(jsonStr)));
      }
    }
    return list;
  }

  static Future<void> clearHistory() async {
    final box = await _openBox(HiveBoxes.recentPlays);
    await box.clear();
  }

  // Queue persistence helpers
  static const String _kCurrentQueueKey = 'current_queue';

  static Future<void> saveQueue(List<StreamingData> queue) async {
    final box = await _openBox(HiveBoxes.queue);
    final payload = queue.map((t) => t.toJson()).toList(growable: false);
    await box.put(_kCurrentQueueKey, jsonEncode(payload));
  }

  static Future<List<StreamingData>> loadQueue() async {
    final box = await _openBox(HiveBoxes.queue);
    final raw = box.get(_kCurrentQueueKey);
    if (raw == null) return <StreamingData>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => StreamingData.fromJson(m))
          .toList();
    } catch (_) {
      await box.delete(_kCurrentQueueKey);
      return <StreamingData>[];
    }
  }

  static Future<void> appendToQueue(StreamingData track) async {
    final q = await loadQueue();
    q.add(track);
    await saveQueue(q);
  }

  static Future<void> insertNext(StreamingData track) async {
    final q = await loadQueue();
    q.insert(0, track);
    await saveQueue(q);
  }

  static Future<void> removeFromQueue(String videoId) async {
    final q = await loadQueue();
    q.removeWhere((t) => t.videoId == videoId);
    await saveQueue(q);
  }

  static Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final q = await loadQueue();
    if (oldIndex < 0 || oldIndex >= q.length) return;
    final item = q.removeAt(oldIndex);
    final insertIndex = newIndex.clamp(0, q.length);
    q.insert(insertIndex, item);
    await saveQueue(q);
  }

  static Future<void> clearQueue() async {
    final box = await _openBox(HiveBoxes.queue);
    await box.delete(_kCurrentQueueKey);
  }
}

