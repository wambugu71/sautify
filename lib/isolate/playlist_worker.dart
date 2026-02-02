/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Message pattern: { 'cmd': 'build', 'tracks': List<Map<String,dynamic>>, 'requestId': int }
/// Each track map should contain fields: videoId,title,artist,thumbnailUrl,durationMs,streamUrl,isLocal,isReady
/// Returns: { 'requestId': int, 'children': List<Map<String,dynamic>>, 'readyIndices': List<int> }
/// We only perform lightweight filtering & pass back a simplified list used to construct AudioSources on main isolate.
void playlistWorkerEntry(SendPort sendPort) {
  final ReceivePort rp = ReceivePort();
  sendPort.send(rp.sendPort);

  final yt = YoutubeExplode();
  final httpClient = HttpClient();
  bool cancelled = false;
  int activeRequestId = -1;
  rp.listen((dynamic message) async {
    if (message is! Map) return;
    final String? cmd = message['cmd'] as String?;
    if (cmd == null) return;
    switch (cmd) {
      case 'build':
        _handleBuild(message, sendPort);
        break;
      case 'buildAndResolve':
        cancelled = false;
        activeRequestId = message['requestId'] as int? ?? -1;
        final progressive = message['progressive'] == true;
        if (progressive) {
          await _handleBuildAndResolveProgressive(
            message,
            sendPort,
            yt,
            httpClient,
            () => cancelled || (message['requestId'] != activeRequestId),
          );
        } else {
          await _handleBuildAndResolve(message, sendPort, yt, httpClient);
        }
        break;
      case 'cancel':
        cancelled = true; // progressive loop checks this via closure
        break;
    }
  });
}

void _handleBuild(Map message, SendPort sendPort) {
  final int requestId = message['requestId'] as int? ?? -1;
  final List<dynamic> raw = message['tracks'] as List<dynamic>? ?? const [];
  final List<Map<String, dynamic>> children = <Map<String, dynamic>>[];
  final List<int> readyIndices = <int>[];
  for (int i = 0; i < raw.length; i++) {
    final t = raw[i] as Map<String, dynamic>;
    final bool isReady =
        (t['isReady'] as bool? ?? false) && (t['streamUrl'] != null);
    if (isReady) {
      readyIndices.add(i);
      children.add({
        'videoId': t['videoId'],
        'title': t['title'],
        'artist': t['artist'],
        'durationMs': t['durationMs'],
        'streamUrl': t['streamUrl'],
        'thumbnailUrl': t['thumbnailUrl'],
        'isLocal': t['isLocal'] ?? false,
      });
    }
  }
  sendPort.send({
    'requestId': requestId,
    'children': children,
    'readyIndices': readyIndices,
  });
}

Future<void> _handleBuildAndResolve(
  Map message,
  SendPort sendPort,
  YoutubeExplode yt,
  HttpClient httpClient,
) async {
  final int requestId = message['requestId'] as int? ?? -1;
  final String quality = (message['quality'] as String?) ?? 'medium';
  final String resolverPref =
      (message['resolverPref'] as String?)?.trim().toLowerCase() ?? 'default';
  final List<dynamic> raw = message['tracks'] as List<dynamic>? ?? const [];
  final List<Map<String, dynamic>> resolved = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> failed = <Map<String, dynamic>>[];

  for (int i = 0; i < raw.length; i++) {
    final Map<String, dynamic> t = raw[i] as Map<String, dynamic>;
    final bool alreadyReady =
        (t['isReady'] as bool? ?? false) && (t['streamUrl'] != null);
    if (alreadyReady) {
      resolved.add({
        'index': i,
        'videoId': t['videoId'],
        'title': t['title'],
        'artist': t['artist'],
        'durationMs': t['durationMs'],
        'streamUrl': t['streamUrl'],
        'thumbnailUrl': t['thumbnailUrl'],
        'isLocal': t['isLocal'] ?? false,
      });
      continue;
    }
    try {
      final r = await _resolveStreaming(
        yt: yt,
        videoId: t['videoId'] as String,
        quality: quality,
        httpClient: httpClient,
        resolverPref: resolverPref,
      );
      if (r != null) {
        resolved.add({
          'index': i,
          'videoId': t['videoId'],
          'title': r['title'] ?? t['title'],
          'artist': r['artist'] ?? t['artist'],
          'durationMs': r['durationMs'] ?? t['durationMs'],
          'streamUrl': r['streamUrl'],
          'thumbnailUrl': r['thumbnailUrl'] ?? t['thumbnailUrl'],
          'isLocal': t['isLocal'] ?? false,
        });
      } else {
        failed.add({'index': i, 'videoId': t['videoId']});
      }
    } catch (e) {
      failed.add({'index': i, 'videoId': t['videoId'], 'error': e.toString()});
    }
  }

  sendPort.send({
    'requestId': requestId,
    'type': 'resolveDone',
    'resolved': resolved,
    'failed': failed,
  });
}

Future<Map<String, dynamic>?> _resolveStreaming({
  required YoutubeExplode yt,
  required String videoId,
  required String quality,
  required HttpClient httpClient,
  required String resolverPref,
}) async {
  final pref = resolverPref;

  if (pref == 'api') {
    return await _resolveViaOkatsu(httpClient, videoId);
  }
  if (pref == 'ytexplode' || pref == 'yt_explode' || pref == 'yt-explode') {
    return await _resolveViaYouTubeExplode(yt, videoId, quality);
  }

  // Default: Try Okatsu first, then fallback to YouTubeExplode.
  final okatsu = await _resolveViaOkatsu(httpClient, videoId);
  if (okatsu != null) return okatsu;

  return await _resolveViaYouTubeExplode(yt, videoId, quality);
}

Future<Map<String, dynamic>?> _resolveViaYouTubeExplode(
  YoutubeExplode yt,
  String videoId,
  String quality,
) async {
  try {
    final video = await yt.videos.get(videoId);
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    // Prefer MP4 (m4a) to keep downloaded files taggable.
    final audioOnly = manifest.audioOnly.toList();
    Iterable<AudioStreamInfo> preferred = audioOnly.where(
      (s) => s.container.name == 'mp4' || s.container.name == 'm4a',
    );
    Iterable<AudioStreamInfo> alt = audioOnly.where(
      (s) => s.container.name != 'mp4',
    );
    int minBps;
    switch (quality) {
      case 'high':
        minBps = 256000;
        break;
      case 'low':
        minBps = 64000;
        break;
      case 'medium':
      default:
        minBps = 128000;
        break;
    }
    AudioStreamInfo? audioStream = preferred
        .where((s) => s.bitrate.bitsPerSecond >= minBps)
        .fold<AudioStreamInfo?>(null, (best, s) {
      if (best == null) return s;
      return s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond ? s : best;
    });
    audioStream ??= alt
        .where((s) => s.bitrate.bitsPerSecond >= minBps)
        .fold<AudioStreamInfo?>(null, (best, s) {
      if (best == null) return s;
      return s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond ? s : best;
    });
    audioStream ??= manifest.audioOnly.withHighestBitrate();

    return {
      'title': video.title,
      'artist': video.author,
      'durationMs': video.duration?.inMilliseconds,
      'streamUrl': audioStream.url.toString(),
      'thumbnailUrl': video.thumbnails.highResUrl,
    };
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> _resolveViaOkatsu(
  HttpClient httpClient,
  String videoId,
) async {
  if (videoId.startsWith('local_') || videoId.startsWith('local:')) {
    return null;
  }
  final url = Uri.parse(
    'https://wambugu-music.vercel.app/download?url=https://www.youtube.com/watch?v=$videoId',
  );
  try {
    final req = await httpClient.getUrl(url);
    req.headers.set('Accept', 'application/json, text/plain, */*');
    req.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118 Safari/537.36',
    );
    final resp = await req.close();
    if (resp.statusCode != 200) return null;
    final text = await resp.transform(utf8.decoder).join();
    final Map<String, dynamic> json = jsonDecode(text) as Map<String, dynamic>;

    Map<String, dynamic> normalized;
    if (json.containsKey('dl') || json.containsKey('thumb')) {
      // Legacy Okatsu-like: {status, dl, title, thumb, duration}
      normalized = <String, dynamic>{
        'status': json['status'] == true,
        'dl': json['dl'],
        'title': json['title'],
        'thumb': json['thumb'],
        'duration': json['duration'],
      };
    } else {
      // New API: {status, result:{title, thumbnail, duration, download_url}}
      final result = json['result'];
      if (result is Map) {
        normalized = <String, dynamic>{
          'status': json['status'] == true,
          'dl': result['download_url'] ?? result['downloadUrl'] ?? result['dl'],
          'title': result['title'] ?? json['title'],
          'thumb': result['thumbnail'] ?? result['thumb'] ?? json['thumb'],
          'duration': result['duration'] ?? json['duration'],
        };
      } else {
        normalized = <String, dynamic>{'status': json['status'] == true};
      }
    }

    if (normalized['status'] != true) return null;
    final String? dl = normalized['dl'] as String?;
    if (dl == null || dl.isEmpty || !dl.startsWith('http')) return null;
    final String title = (normalized['title'] as String?) ?? 'Unknown';
    final String? thumb = normalized['thumb'] as String?;
    final int? durationSec = (normalized['duration'] as num?)?.toInt();
    return {
      'title': title,
      'artist': 'Unknown Artist',
      'durationMs': durationSec != null ? durationSec * 1000 : null,
      'streamUrl': dl,
      'thumbnailUrl': thumb,
    };
  } catch (_) {
    return null;
  }
}

Future<void> _handleBuildAndResolveProgressive(
  Map message,
  SendPort sendPort,
  YoutubeExplode yt,
  HttpClient httpClient,
  bool Function() isCancelled,
) async {
  final int requestId = message['requestId'] as int? ?? -1;
  final String quality = (message['quality'] as String?) ?? 'medium';
  final String resolverPref =
      (message['resolverPref'] as String?)?.trim().toLowerCase() ?? 'default';
  final int priorityIndex = message['priorityIndex'] as int? ?? 0;
  final int configuredBatchSize = message['batchSize'] as int? ?? 6;
  final int concurrency = message['concurrency'] as int? ?? 4;
  final List<dynamic> raw = message['tracks'] as List<dynamic>? ?? const [];
  if (raw.isEmpty) {
    sendPort.send({
      'requestId': requestId,
      'type': 'done',
      'resolved': <Map<String, dynamic>>[],
      'failed': <Map<String, dynamic>>[],
      'elapsedMs': 0,
    });
    return;
  }

  final indices = List<int>.generate(raw.length, (i) => i);
  if (priorityIndex >= 0 && priorityIndex < indices.length) {
    indices.remove(priorityIndex);
    indices.insert(0, priorityIndex);
  }
  for (int off = 1; off <= 3; off++) {
    final ni = priorityIndex + off;
    if (ni < raw.length && indices.contains(ni)) {
      indices.remove(ni);
      indices.insert(off, ni);
    }
  }

  final resolved = <Map<String, dynamic>>[];
  final failed = <Map<String, dynamic>>[];
  final Stopwatch sw = Stopwatch()..start();
  int sinceLastEmit = 0;
  // For first wave we want ultra-fast emissions (priority + next 2) regardless of batch size
  final Set<int> critical = {
    priorityIndex,
    if (priorityIndex + 1 < raw.length) priorityIndex + 1,
    if (priorityIndex + 2 < raw.length) priorityIndex + 2,
  };

  final pending = <Future<void>>[];
  int active = 0;
  int cursor = 0;

  Future<void> scheduleNext() async {
    if (isCancelled()) return;
    if (cursor >= indices.length) return;
    final idx = indices[cursor++];
    final Map<String, dynamic> t = raw[idx] as Map<String, dynamic>;
    final alreadyReady =
        (t['isReady'] as bool? ?? false) && (t['streamUrl'] != null);
    active++;
    final fut = () async {
      try {
        Map<String, dynamic>? r;
        if (alreadyReady) {
          r = {
            'title': t['title'],
            'artist': t['artist'],
            'durationMs': t['durationMs'],
            'streamUrl': t['streamUrl'],
            'thumbnailUrl': t['thumbnailUrl'],
          };
        } else {
          r = await _resolveStreaming(
            yt: yt,
            videoId: t['videoId'] as String,
            quality: quality,
            httpClient: httpClient,
            resolverPref: resolverPref,
          );
        }
        if (r != null) {
          resolved.add({
            'index': idx,
            'videoId': t['videoId'],
            'title': r['title'] ?? t['title'],
            'artist': r['artist'] ?? t['artist'],
            'durationMs': r['durationMs'] ?? t['durationMs'],
            'streamUrl': r['streamUrl'],
            'thumbnailUrl': r['thumbnailUrl'] ?? t['thumbnailUrl'],
            'isLocal': t['isLocal'] ?? false,
          });
        } else {
          failed.add({'index': idx, 'videoId': t['videoId']});
        }
      } catch (e) {
        failed.add({
          'index': idx,
          'videoId': t['videoId'],
          'error': e.toString(),
        });
      } finally {
        active--;
        sinceLastEmit++;
        final priorityResolved = resolved.any(
          (m) => m['index'] == priorityIndex,
        );
        final newlyResolvedCritical =
            resolved.where((m) => critical.contains(m['index'])).length;
        final int dynamicBatchSize =
            (resolved.length < 8) ? 3 : configuredBatchSize;
        // Emit conditions:
        // 1. Immediate when a critical track resolves and wasn't yet emitted individually.
        // 2. When accumulated sinceLastEmit reaches dynamic batch size.
        // 3. When all tasks done (active == 0).
        if (priorityResolved &&
            newlyResolvedCritical > 0 &&
            sinceLastEmit > 0) {
          sendPort.send({
            'requestId': requestId,
            'type': 'progress',
            'resolved': List<Map<String, dynamic>>.from(resolved),
            'failed': List<Map<String, dynamic>>.from(failed),
            'remaining': raw.length - (resolved.length + failed.length),
            'elapsedMs': sw.elapsedMilliseconds,
          });
          sinceLastEmit = 0;
        } else if (sinceLastEmit >= dynamicBatchSize || (active == 0)) {
          sendPort.send({
            'requestId': requestId,
            'type': 'progress',
            'resolved': List<Map<String, dynamic>>.from(resolved),
            'failed': List<Map<String, dynamic>>.from(failed),
            'remaining': raw.length - (resolved.length + failed.length),
            'elapsedMs': sw.elapsedMilliseconds,
          });
          sinceLastEmit = 0;
        }
        if (!isCancelled()) {
          while (active < concurrency && cursor < indices.length) {
            await scheduleNext();
          }
        }
      }
    }();
    pending.add(fut);
  }

  while (active < concurrency && cursor < indices.length && !isCancelled()) {
    await scheduleNext();
  }

  await Future.wait(pending);
  if (isCancelled()) return;
  sw.stop();
  sendPort.send({
    'requestId': requestId,
    'type': 'done',
    'resolved': resolved,
    'failed': failed,
    'elapsedMs': sw.elapsedMilliseconds,
  });
}

