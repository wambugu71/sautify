/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

/*
DownloadManager: simple queueing download manager with retries, cancel and progress.
*/

import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';

class DownloadTask {
  final String id;
  final String url;
  final String savePath;
  final Completer<void> _completer = Completer<void>();
  final CancelToken cancelToken = CancelToken();
  int attempts = 0;

  DownloadTask({required this.id, required this.url, required this.savePath});

  Future<void> get done => _completer.future;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void fail([Object? e]) {
    if (!_completer.isCompleted) _completer.completeError(e ?? 'failed');
  }

  void cancel() {
    cancelToken.cancel('cancelled');
    if (!_completer.isCompleted) _completer.completeError('cancelled');
  }
}

typedef ProgressCallback = void Function(int received, int total);

class DownloadManager {
  static DownloadManager? _instance;
  factory DownloadManager() => _instance ??= DownloadManager._internal();
  DownloadManager._internal();

  final Dio _dio = Dio();
  final Map<String, DownloadTask> _active = {};
  final Queue<DownloadTask> _queue = Queue<DownloadTask>();
  final int _concurrency = 2;
  int _running = 0;

  StreamController<Map<String, dynamic>>? _events;

  Stream<Map<String, dynamic>> events() {
    _events ??= StreamController.broadcast();
    return _events!.stream;
  }

  Future<void> startDownload(
    String id,
    String url,
    String savePath, {
    ProgressCallback? onProgress,
    int maxRetries = 3,
  }) async {
    if (_active.containsKey(id) || _queue.any((t) => t.id == id)) return;
    final task = DownloadTask(id: id, url: url, savePath: savePath);
    _queue.add(task);
    _events?.add({'event': 'queued', 'id': id});
    _processQueue(onProgress: onProgress, maxRetries: maxRetries);
  }

  void _processQueue({ProgressCallback? onProgress, int maxRetries = 3}) {
    while (_running < _concurrency && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _runTask(task, onProgress: onProgress, maxRetries: maxRetries);
    }
  }

  void _runTask(DownloadTask task,
      {ProgressCallback? onProgress, int maxRetries = 3}) {
    _running++;
    _active[task.id] = task;

    () async {
      try {
        while (task.attempts < maxRetries) {
          task.attempts++;
          try {
            await _dio.download(
              task.url,
              task.savePath,
              cancelToken: task.cancelToken,
              onReceiveProgress: (received, total) {
                onProgress?.call(received, total);
                _events?.add({
                  'event': 'progress',
                  'id': task.id,
                  'received': received,
                  'total': total
                });
              },
            );
            // success
            task.complete();
            _events?.add({'event': 'done', 'id': task.id});
            break;
          } catch (e) {
            if (e is DioException && CancelToken.isCancel(e)) {
              task.fail('cancelled');
              _events?.add({'event': 'cancelled', 'id': task.id});
              break;
            }
            if (task.attempts >= maxRetries) {
              task.fail(e);
              _events?.add(
                  {'event': 'error', 'id': task.id, 'error': e.toString()});
              break;
            }
            // otherwise retry after a short delay
            await Future.delayed(Duration(milliseconds: 500 * task.attempts));
          }
        }
      } finally {
        _active.remove(task.id);
        _running--;
        // process next queued
        _processQueue(onProgress: onProgress, maxRetries: maxRetries);
      }
    }();
  }

  bool isDownloading(String id) =>
      _active.containsKey(id) || _queue.any((t) => t.id == id);

  /// Returns a snapshot of queued download ids (in-order).
  List<String> queuedIds() => _queue.map((t) => t.id).toList(growable: false);

  /// Returns a snapshot of active download ids.
  List<String> activeIds() => _active.keys.toList(growable: false);

  void cancel(String id) {
    final active = _active[id];
    if (active != null) {
      active.cancel();
      return;
    }
    // Cancel queued
    DownloadTask? found;
    for (final t in _queue) {
      if (t.id == id) {
        found = t;
        break;
      }
    }
    if (found != null) {
      _queue.remove(found);
      _events?.add({'event': 'cancelled', 'id': id});
    }
  }

  void dispose() {
    for (final t in _active.values) {
      t.cancel();
    }
    _queue.clear();
    _events?.close();
  }
}

