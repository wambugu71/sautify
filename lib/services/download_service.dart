/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:isolate';

import 'package:dio/dio.dart';

class DownloadService {
  static Future<void> startDownload({
    required String url,
    required String savePath,
    required Function(int received, int total) onProgress,
    required Function() onDone,
    required Function(String error) onError,
  }) async {
    final receivePort = ReceivePort();

    try {
      await Isolate.spawn(_downloadWorker, {
        'url': url,
        'savePath': savePath,
        'sendPort': receivePort.sendPort,
      });

      receivePort.listen((message) {
        if (message is Map) {
          final status = message['status'];
          if (status == 'progress') {
            final received = message['received'] as int;
            final total = message['total'] as int;
            onProgress(received, total);
          } else if (status == 'done') {
            receivePort.close();
            onDone();
          } else if (status == 'error') {
            receivePort.close();
            onError(message['message'] as String);
          }
        }
      });
    } catch (e) {
      onError(e.toString());
      receivePort.close();
    }
  }
}

void _downloadWorker(Map<String, dynamic> args) async {
  final url = args['url'] as String;
  final savePath = args['savePath'] as String;
  final sendPort = args['sendPort'] as SendPort;
  final dio = Dio();

  try {
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        sendPort.send({
          'status': 'progress',
          'received': received,
          'total': total,
        });
      },
    );
    sendPort.send({'status': 'done'});
  } catch (e) {
    sendPort.send({'status': 'error', 'message': e.toString()});
  }
}

