/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
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
      // Prune if too large
      if (b.length > 200) {
        // Run in background to avoid blocking
        Future.microtask(() => _pruneCache(b));
      }
    } catch (_) {}
  }

  Future<void> _pruneCache(Box<String> b) async {
    try {
      final keys = b.keys.toList(growable: false);
      final entries = <String, DateTime>{};

      // 1. Collect timestamps
      for (final key in keys) {
        final raw = b.get(key);
        if (raw == null) continue;
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final data = StreamingData.fromJson(map);
          if (data.isExpired) {
            await b.delete(key);
            continue;
          }
          entries[key.toString()] = data.cachedAt;
        } catch (_) {
          await b.delete(key);
        }
      }

      // 2. If still too big, remove oldest
      if (b.length > 150) {
        final sorted = entries.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        final toRemove = sorted.take(sorted.length - 150);
        for (final e in toRemove) {
          await b.delete(e.key);
        }
      }
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

