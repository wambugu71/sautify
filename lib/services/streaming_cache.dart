/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class StreamingCache {
  static const String _boxName = 'stream_cache';
  Box<String>? _box;
  bool _initializing = false;

  Future<void> ensureInitialized() async {
    if (_box != null || _initializing) return;
    _initializing = true;
    try {
      try {
        await Hive.initFlutter();
      } catch (_) {
        // Already initialized
      }
      _box = Hive.isBoxOpen(_boxName)
          ? Hive.box<String>(_boxName)
          : await Hive.openBox<String>(_boxName);
    } finally {
      _initializing = false;
    }
  }

  Future<StreamingData?> get(String videoId) async {
    await ensureInitialized();
    final b = _box;
    if (b == null) return null;
    final raw = b.get(videoId);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final data = StreamingData.fromJson(map);
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String videoId, StreamingData data) async {
    await ensureInitialized();
    final b = _box;
    if (b == null) return;
    try {
      await b.put(videoId, jsonEncode(data.toJson()));
    } catch (_) {}
  }

  Future<void> remove(String videoId) async {
    await ensureInitialized();
    final b = _box;
    if (b == null) return;
    await b.delete(videoId);
  }

  Future<void> clearExpired() async {
    await ensureInitialized();
    final b = _box;
    if (b == null) return;
    final keys = b.keys.toList(growable: false);
    for (final key in keys) {
      final raw = b.get(key);
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final data = StreamingData.fromJson(map);
        if (data.isExpired) {
          await b.delete(key);
        }
      } catch (_) {
        // If corrupted, remove entry
        await b.delete(key);
      }
    }
  }
}
