/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sautifyv2/db/hive_boxes.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class MetadataOverridesStore {
  static Box<String>? _box;
  static Future<void>? _initFuture;

  static Future<void> ensureReady() {
    final existing = _initFuture;
    if (existing != null) return existing;

    final fut = () async {
      await HiveBoxes.init();
      _box ??= Hive.isBoxOpen(HiveBoxes.metadataOverrides)
          ? Hive.box<String>(HiveBoxes.metadataOverrides)
          : await Hive.openBox<String>(HiveBoxes.metadataOverrides);
    }();

    _initFuture = fut;
    return fut;
  }

  static ValueListenable<Box<String>>? listenable() {
    final b = _box;
    return b?.listenable();
  }

  static String keyForTrack(StreamingData t) {
    final streamUrl = (t.streamUrl ?? '').trim();
    if (t.isLocal && streamUrl.isNotEmpty) {
      return 'path:$streamUrl';
    }
    final localId = t.localId;
    if (t.isLocal && localId != null) {
      return 'local:$localId';
    }
    return 'id:${t.videoId}';
  }

  static Map<String, dynamic>? _getRawSync(String key) {
    final b = _box;
    if (b == null) return null;
    final s = b.get(key);
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static StreamingData maybeApplySync(StreamingData t) {
    final raw = _getRawSync(keyForTrack(t));
    if (raw == null) return t;
    final title = (raw['title'] as String?)?.trim();
    final artist = (raw['artist'] as String?)?.trim();
    return t.copyWith(
      title: (title != null && title.isNotEmpty) ? title : t.title,
      artist: (artist != null && artist.isNotEmpty) ? artist : t.artist,
    );
  }

  static Future<void> setOverrideForTrack(
    StreamingData t, {
    required String title,
    required String artist,
  }) async {
    await ensureReady();
    final key = keyForTrack(t);
    final payload = <String, dynamic>{
      'title': title.trim(),
      'artist': artist.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _box!.put(key, jsonEncode(payload));
  }

  static Future<void> removeOverrideForTrack(StreamingData t) async {
    await ensureReady();
    await _box!.delete(keyForTrack(t));
  }
}

