/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

/*
Small QueueService wrapper that standardizes queue actions and persistence.
*/

import 'dart:async';

import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/audio_player_service.dart';

class QueueService {
  static QueueService? _instance;
  factory QueueService() => _instance ??= QueueService._internal();
  QueueService._internal();

  final AudioPlayerService _audio = AudioPlayerService();

  Future<void> playNext(StreamingData track) async {
    final insertAt = _audio.currentIndex + 1;
    await _audio.insertTrack(insertAt, track);
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> addToEnd(StreamingData track) async {
    final index = _audio.playlist.length;
    await _audio.insertTrack(index, track);
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> addToQueueAndPlayNow(StreamingData track) async {
    // Replace current playlist with this single track and play
    await _audio.replacePlaylist([track], initialIndex: 0, autoPlay: true);
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> removeAt(int index) async {
    await _audio.removeTrack(index);
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> move(int from, int to) async {
    await _audio.moveTrack(from, to);
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> persistCurrentQueue() async {
    await LibraryStore.saveQueue(_audio.playlist);
  }

  Future<void> restorePersistedQueue({bool autoPlay = false}) async {
    final q = await LibraryStore.loadQueue();
    if (q.isEmpty) return;
    await _audio.replacePlaylist(q, initialIndex: 0, autoPlay: autoPlay);
  }
}

