/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:isolate';

import 'package:dart_ytmusic_api/yt_music.dart';

void searchWorkerEntry(SendPort mainSendPort) {
  final ReceivePort rp = ReceivePort();
  mainSendPort.send(rp.sendPort);

  final YTMusic ytmusic = YTMusic();
  bool initialized = false;

  Future<void> ensureInit(
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (initialized) return;
    await ytmusic.initialize().timeout(timeout);
    initialized = true;
  }

  Map<String, dynamic> songToMap(dynamic song) {
    try {
      final thumbs = (song.thumbnails as List?) ?? const [];
      String? thumb;
      if (thumbs.isNotEmpty) {
        final last = thumbs.last;
        try {
          thumb = (last.url as String?);
        } catch (_) {
          thumb = null;
        }
      }

      final int? seconds = song.duration as int?;
      return {
        'videoId': (song.videoId as String?) ?? '',
        'title': (song.name as String?) ?? '',
        'artist': ((song.artist as dynamic).name as String?) ?? '',
        'thumbnailUrl': thumb,
        'durationSeconds': seconds,
      };
    } catch (_) {
      return {
        'videoId': '',
        'title': '',
        'artist': '',
        'thumbnailUrl': null,
        'durationSeconds': null,
      };
    }
  }

  Map<String, dynamic> albumToMap(dynamic album) {
    try {
      final thumbs = (album.thumbnails as List?) ?? const [];
      String? thumb;
      if (thumbs.isNotEmpty) {
        final last = thumbs.last;
        try {
          thumb = (last.url as String?);
        } catch (_) {
          thumb = null;
        }
      }

      return {
        'albumId': (album.albumId as String?) ?? '',
        'playlistId': (album.playlistId as String?) ?? '',
        'title': (album.name as String?) ?? '',
        'artist': ((album.artist as dynamic).name as String?) ?? '',
        'thumbnailUrl': thumb,
      };
    } catch (_) {
      return {
        'albumId': '',
        'playlistId': '',
        'title': '',
        'artist': '',
        'thumbnailUrl': null,
      };
    }
  }

  rp.listen((message) async {
    if (message is! Map) return;
    final cmd = message['cmd']?.toString();
    final int requestId = (message['requestId'] as int?) ?? -1;
    final SendPort? replyTo = message['replyTo'] as SendPort?;
    if (replyTo == null) return;

    try {
      if (cmd == 'init') {
        await ensureInit(
          timeout:
              Duration(milliseconds: (message['timeoutMs'] as int?) ?? 15000),
        );
        replyTo.send({'type': 'init', 'requestId': requestId, 'ok': true});
        return;
      }

      if (cmd == 'suggestions') {
        await ensureInit();
        final q = (message['query'] as String?) ?? '';
        final timeoutMs = (message['timeoutMs'] as int?) ?? 8000;
        final res = await ytmusic
            .getSearchSuggestions(q)
            .timeout(Duration(milliseconds: timeoutMs));
        replyTo.send({
          'type': 'suggestions',
          'requestId': requestId,
          'ok': true,
          'suggestions': List<String>.from(res.map((e) => e.toString())),
        });
        return;
      }

      if (cmd == 'search') {
        await ensureInit();
        final q = (message['query'] as String?) ?? '';
        final timeoutMs = (message['timeoutMs'] as int?) ?? 12000;
        final songsFut =
            ytmusic.searchSongs(q).timeout(Duration(milliseconds: timeoutMs));
        final albumsFut =
            ytmusic.searchAlbums(q).timeout(Duration(milliseconds: timeoutMs));

        final results = await Future.wait([
          songsFut,
          albumsFut,
        ]);

        final songs = results.isNotEmpty ? results[0] : <dynamic>[];
        final albums = results.length > 1 ? results[1] : <dynamic>[];

        final mappedSongs = <Map<String, dynamic>>[];
        for (final s in songs) {
          mappedSongs.add(songToMap(s));
        }

        final mappedAlbums = <Map<String, dynamic>>[];
        for (final a in albums) {
          mappedAlbums.add(albumToMap(a));
        }

        replyTo.send({
          'type': 'search',
          'requestId': requestId,
          'ok': true,
          'songs': mappedSongs,
          'albums': mappedAlbums,
        });
        return;
      }

      if (cmd == 'albumTracks') {
        await ensureInit();
        final albumId = (message['albumId'] as String?) ?? '';
        final timeoutMs = (message['timeoutMs'] as int?) ?? 12000;
        final album = await ytmusic
            .getAlbum(albumId)
            .timeout(Duration(milliseconds: timeoutMs));

        final dynamic tracksDynamic = (album as dynamic).tracks;
        final List<dynamic> tracks = tracksDynamic is List
            ? List<dynamic>.from(tracksDynamic)
            : <dynamic>[];

        final mapped = <Map<String, dynamic>>[];
        for (final t in tracks) {
          mapped.add(songToMap(t));
        }

        replyTo.send({
          'type': 'albumTracks',
          'requestId': requestId,
          'ok': true,
          'tracks': mapped,
        });
        return;
      }

      replyTo.send({
        'type': cmd ?? 'unknown',
        'requestId': requestId,
        'ok': false,
        'error': 'Unknown cmd: $cmd',
      });
    } catch (e) {
      replyTo.send({
        'type': cmd ?? 'error',
        'requestId': requestId,
        'ok': false,
        'error': e.toString(),
      });
    }
  });
}

