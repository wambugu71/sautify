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

class ContinueListeningSession {
  final List<StreamingData> playlist;
  final int currentIndex;
  final Duration position;
  final String? sourceType;
  final String? sourceName;
  final DateTime updatedAt;

  const ContinueListeningSession({
    required this.playlist,
    required this.currentIndex,
    required this.position,
    required this.updatedAt,
    this.sourceType,
    this.sourceName,
  });

  StreamingData? get currentTrack {
    if (playlist.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= playlist.length) return null;
    return playlist[currentIndex];
  }

  Map<String, dynamic> toJson() => {
        'playlist': playlist.map((t) => t.toJson()).toList(growable: false),
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'sourceType': sourceType,
        'sourceName': sourceName,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static ContinueListeningSession? fromJson(Map<String, dynamic> json) {
    try {
      final list = (json['playlist'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  StreamingData.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(growable: false) ??
          const <StreamingData>[];

      if (list.isEmpty) return null;

      final idx = (json['currentIndex'] as num?)?.toInt() ?? 0;
      final posMs = (json['positionMs'] as num?)?.toInt() ?? 0;
      final updatedAtStr = json['updatedAt'] as String?;
      final updatedAt = updatedAtStr != null
          ? (DateTime.tryParse(updatedAtStr) ?? DateTime.now())
          : DateTime.now();

      return ContinueListeningSession(
        playlist: list,
        currentIndex: idx.clamp(0, list.length - 1),
        position: Duration(milliseconds: posMs.clamp(0, 1 << 30)),
        sourceType: json['sourceType'] as String?,
        sourceName: json['sourceName'] as String?,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }
}

class ContinueListeningStore {
  static const String _kSessionKey = 'session';

  static Box<String>? _box;
  static Future<void>? _initFuture;

  static Future<void> ensureReady() {
    final existing = _initFuture;
    if (existing != null) return existing;

    final fut = () async {
      await HiveBoxes.init();
      _box ??= Hive.isBoxOpen(HiveBoxes.continueListening)
          ? Hive.box<String>(HiveBoxes.continueListening)
          : await Hive.openBox<String>(HiveBoxes.continueListening);
    }();

    _initFuture = fut;
    return fut;
  }

  static ValueListenable<Box<String>>? listenable() {
    final b = _box;
    return b?.listenable(keys: const [_kSessionKey]);
  }

  static ContinueListeningSession? loadSync() {
    final b = _box;
    if (b == null) return null;
    final s = b.get(_kSessionKey);
    if (s == null || s.isEmpty) return null;
    try {
      return ContinueListeningSession.fromJson(
        jsonDecode(s) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(ContinueListeningSession session) async {
    await ensureReady();
    await _box!.put(_kSessionKey, jsonEncode(session.toJson()));
  }

  static Future<void> clear() async {
    await ensureReady();
    await _box!.delete(_kSessionKey);
  }
}

