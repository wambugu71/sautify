/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:isolate';

import '../isolate/search_worker.dart' show searchWorkerEntry;

class SearchWorkerService {
  SearchWorkerService._();
  static final SearchWorkerService instance = SearchWorkerService._();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerSendPort;

  int _requestCounter = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  Future<void> _ensureStarted() async {
    if (_workerSendPort != null) return;

    final rp = ReceivePort();
    _receivePort = rp;

    final ready = Completer<SendPort>();
    rp.listen((message) {
      if (message is SendPort && !ready.isCompleted) {
        ready.complete(message);
        return;
      }
      if (message is Map) {
        final reqId = message['requestId'] as int?;
        if (reqId != null) {
          final c = _pending.remove(reqId);
          if (c != null && !c.isCompleted) {
            c.complete(Map<String, dynamic>.from(message));
          }
        }
      }
    });

    _isolate = await Isolate.spawn(
      searchWorkerEntry,
      rp.sendPort,
      debugName: 'search_worker',
      errorsAreFatal: false,
    );

    _workerSendPort = await ready.future.timeout(const Duration(seconds: 5));
  }

  Future<Map<String, dynamic>> _request(
    String cmd,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _ensureStarted();
    final send = _workerSendPort;
    final rp = _receivePort;
    if (send == null || rp == null) {
      throw StateError('Search worker not available');
    }

    final reqId = ++_requestCounter;
    final c = Completer<Map<String, dynamic>>();
    _pending[reqId] = c;

    send.send({
      'cmd': cmd,
      'requestId': reqId,
      'replyTo': rp.sendPort,
      ...payload,
    });

    final res = await c.future.timeout(timeout);
    final ok = (res['ok'] as bool?) ?? false;
    if (!ok) {
      throw Exception((res['error'] as String?) ?? 'Search worker error');
    }
    return res;
  }

  Future<void> initializeIfNeeded(
      {Duration timeout = const Duration(seconds: 15)}) async {
    await _request(
      'init',
      {'timeoutMs': timeout.inMilliseconds},
      timeout: timeout + const Duration(seconds: 2),
    );
  }

  Future<List<String>> suggestions(
    String query, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final res = await _request(
      'suggestions',
      {
        'query': query,
        'timeoutMs': timeout.inMilliseconds,
      },
      timeout: timeout + const Duration(seconds: 2),
    );

    return List<String>.from(res['suggestions'] as List? ?? const []);
  }

  Future<
      ({
        List<Map<String, dynamic>> songs,
        List<Map<String, dynamic>> albums
      })> search(
    String query, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final res = await _request(
      'search',
      {
        'query': query,
        'timeoutMs': timeout.inMilliseconds,
      },
      timeout: timeout + const Duration(seconds: 2),
    );

    final songs = (res['songs'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
    final albums = (res['albums'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);

    return (songs: songs, albums: albums);
  }

  Future<List<Map<String, dynamic>>> albumTracks(
    String albumId, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final res = await _request(
      'albumTracks',
      {
        'albumId': albumId,
        'timeoutMs': timeout.inMilliseconds,
      },
      timeout: timeout + const Duration(seconds: 2),
    );

    return (res['tracks'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  void dispose() {
    try {
      _receivePort?.close();
    } catch (_) {}
    _receivePort = null;
    _workerSendPort = null;

    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;

    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Search worker disposed'));
      }
    }
    _pending.clear();
  }
}

