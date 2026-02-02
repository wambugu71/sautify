/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/blocs/player/player_state.dart';

class LyricsCacheEntry {
  final List<LyricLine> lines;
  final String? source;
  final DateTime cachedAt;

  const LyricsCacheEntry({
    required this.lines,
    required this.cachedAt,
    this.source,
  });
}

class LyricsCache {
  static const String _boxName = 'lyrics_cache';

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

  Future<LyricsCacheEntry?> get(String videoId) async {
    await ensureInitialized();
    final b = _box;
    if (b == null) return null;

    final raw = b.get(videoId);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAtMs = (map['cachedAt'] as num?)?.toInt();
      final source = map['source'] as String?;
      final linesRaw = map['lines'];
      if (cachedAtMs == null || linesRaw is! List) return null;

      final lines = <LyricLine>[];
      for (final item in linesRaw) {
        if (item is! Map) continue;
        final text = item['t']?.toString() ?? '';
        final start = (item['s'] as num?)?.toInt() ?? 0;
        final end = (item['e'] as num?)?.toInt() ?? (start + 2000);
        if (text.trim().isEmpty) continue;
        lines.add(LyricLine(text, start, end));
      }

      if (lines.isEmpty) return null;

      return LyricsCacheEntry(
        lines: lines,
        source: source,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
      );
    } catch (_) {
      // Corrupted entry; best-effort cleanup
      try {
        await b.delete(videoId);
      } catch (_) {}
      return null;
    }
  }

  Future<void> set(
    String videoId,
    List<LyricLine> lines, {
    String? source,
  }) async {
    if (lines.isEmpty) return;

    await ensureInitialized();
    final b = _box;
    if (b == null) return;

    try {
      final payload = <String, dynamic>{
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'source': source,
        'lines': lines
            .map((l) => <String, dynamic>{
                  't': l.text,
                  's': l.startTimeMs,
                  'e': l.endTimeMs
                })
            .toList(growable: false),
      };

      await b.put(videoId, jsonEncode(payload));

      // Keep the cache bounded.
      if (b.length > 400) {
        Future.microtask(() => _pruneCache(b));
      }
    } catch (_) {}
  }

  Future<void> _pruneCache(Box<String> b) async {
    try {
      final keys = b.keys.toList(growable: false);
      final entries = <String, int>{};

      for (final key in keys) {
        final raw = b.get(key);
        if (raw == null) continue;
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final cachedAtMs = (map['cachedAt'] as num?)?.toInt();
          if (cachedAtMs == null) {
            await b.delete(key);
            continue;
          }
          entries[key.toString()] = cachedAtMs;
        } catch (_) {
          await b.delete(key);
        }
      }

      // Remove oldest items until under target size.
      const targetSize = 300;
      if (b.length > targetSize) {
        final sorted = entries.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        final toRemoveCount = b.length - targetSize;
        for (final e in sorted.take(toRemoveCount)) {
          await b.delete(e.key);
        }
      }
    } catch (_) {}
  }
}

