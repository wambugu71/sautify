import 'dart:io';
import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

enum _DetectedAudioFormat { mp3, mp4, webm, unknown }

Future<Map<String, dynamic>> finalizeDownloadedFile(
  Map<String, dynamic> args,
) async {
  final originalPath = (args['filePath'] as String?) ?? '';
  if (originalPath.isEmpty) {
    return {
      'finalPath': originalPath,
      'taggingAttempted': false,
      'taggingOk': false,
      'error': 'Missing filePath',
    };
  }

  final title = (args['title'] as String?) ?? '';
  final artist = (args['artist'] as String?) ?? '';
  final thumbUrl = (args['thumbnailUrl'] as String?)?.trim();

  String finalPath = originalPath;

  try {
    finalPath = await _ensureCorrectExtension(originalPath);
  } catch (e) {
    print('[DownloadWorker] Extension fix failed: $e');
    // best-effort
  }

  // Only attempt tagging for formats lofty's backend supports reliably which is my rust backend.
  bool taggingAttempted = false;
  try {
    final format = await _detectAudioFormat(finalPath);
    print('[DownloadWorker] Detected format: $format for $finalPath');
    final canTag = format == _DetectedAudioFormat.mp3 ||
        format == _DetectedAudioFormat.mp4;
    if (!canTag) {
      print('[DownloadWorker] Skipping tagging for format: $format');
      return {
        'finalPath': finalPath,
        'taggingAttempted': false,
        'taggingOk': true,
        'error': null,
      };
    }

    taggingAttempted = true;

    final pictures = <Picture>[];
    if (thumbUrl != null &&
        thumbUrl.isNotEmpty &&
        !thumbUrl.startsWith('file:') &&
        (thumbUrl.startsWith('http://') || thumbUrl.startsWith('https://'))) {
      try {
        print('[DownloadWorker] Fetching artwork from: $thumbUrl');
        final res = await Dio().get<List<int>>(
          thumbUrl,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Accept': 'image/jpeg, image/png, image/webp',
            },
          ),
        );

        var bytes = Uint8List.fromList(res.data ?? const <int>[]);
        if (bytes.isNotEmpty) {
          final ct = (res.headers.value('content-type') ?? '').toLowerCase();
          print('[DownloadWorker] Artwork content-type: $ct');
          MimeType? mime;
          if (ct.contains('png')) mime = MimeType.png;
          if (ct.contains('jpeg') || ct.contains('jpg')) mime = MimeType.jpeg;

          // Handle WebP or other formats by converting to JPEG
          // Also resize if too large to prevent tag write failures
          try {
            img.Image? image = img.decodeImage(bytes);
            if (image != null) {
              // Resize if larger than 600x600 to ensure compatibility
              if (image.width > 600 || image.height > 600) {
                print(
                    '[DownloadWorker] Resizing artwork from ${image.width}x${image.height}');
                image = img.copyResize(
                  image,
                  width: image.width > image.height ? 600 : null,
                  height: image.height > image.width ? 600 : null,
                  maintainAspect: true,
                );
              }

              // Always convert to JPEG for maximum compatibility
              final jpg = img.encodeJpg(image, quality: 85);
              bytes = Uint8List.fromList(jpg);
              mime = MimeType.jpeg;
              print(
                  '[DownloadWorker] Converted artwork to JPEG, size: ${bytes.length}');
            }
          } catch (e) {
            print('[DownloadWorker] Image conversion failed: $e');
            // Conversion failed, try using original bytes if they were jpeg/png
          }

          if (mime != null) {
            final pic = Picture(
              pictureType: PictureType.coverFront,
              mimeType: mime,
              bytes: bytes,
            );
            pictures.add(pic);
          }
        }
      } catch (_) {
        // ignore: cover art is best-effort
      }
    }

    final tag = Tag(
      title: title,
      trackArtist: artist,
      pictures: pictures,
    );

    print('[DownloadWorker] Writing tags to $finalPath');
    // Small delay to ensure file handle is released
    await Future.delayed(const Duration(milliseconds: 200));
    await AudioTags.write(finalPath, tag);
    print('[DownloadWorker] Tagging successful');

    return {
      'finalPath': finalPath,
      'taggingAttempted': taggingAttempted,
      'taggingOk': true,
      'error': null,
    };
  } catch (e, st) {
    print('[DownloadWorker] Tagging failed: $e\n$st');
    return {
      'finalPath': finalPath,
      'taggingAttempted': taggingAttempted,
      'taggingOk': false,
      'error': e.toString(),
    };
  }
}

Future<_DetectedAudioFormat> _detectAudioFormat(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return _DetectedAudioFormat.unknown;
    final raf = await f.open(mode: FileMode.read);
    try {
      final bytes = await raf.read(16);
      if (bytes.length >= 4) {
        // WebM/Matroska (EBML)
        if (bytes[0] == 0x1A &&
            bytes[1] == 0x45 &&
            bytes[2] == 0xDF &&
            bytes[3] == 0xA3) {
          return _DetectedAudioFormat.webm;
        }

        // MP4/M4A: "....ftyp"
        if (bytes.length >= 8 &&
            bytes[4] == 0x66 &&
            bytes[5] == 0x74 &&
            bytes[6] == 0x79 &&
            bytes[7] == 0x70) {
          return _DetectedAudioFormat.mp4;
        }

        // MP3: "ID3" or frame sync
        if (bytes.length >= 3 &&
            bytes[0] == 0x49 &&
            bytes[1] == 0x44 &&
            bytes[2] == 0x33) {
          return _DetectedAudioFormat.mp3;
        }
        if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
          return _DetectedAudioFormat.mp3;
        }
      }
    } finally {
      await raf.close();
    }
  } catch (e) {
    print('[DownloadWorker] Format detection failed: $e');
  }
  return _DetectedAudioFormat.unknown;
}

String _extForFormat(_DetectedAudioFormat f) {
  switch (f) {
    case _DetectedAudioFormat.mp3:
      return '.mp3';
    case _DetectedAudioFormat.mp4:
      return '.m4a';
    case _DetectedAudioFormat.webm:
      return '.webm';
    case _DetectedAudioFormat.unknown:
      return '';
  }
}

Future<String> _ensureCorrectExtension(String originalPath) async {
  final format = await _detectAudioFormat(originalPath);
  final desiredExt = _extForFormat(format);
  if (desiredExt.isEmpty) return originalPath;

  final lower = originalPath.toLowerCase();
  if (lower.endsWith(desiredExt)) return originalPath;

  try {
    final base = originalPath.replaceAll(RegExp(r'\.[^\\/]+$'), '');
    String candidate = '$base$desiredExt';
    int n = 1;
    while (await File(candidate).exists()) {
      candidate = '$base ($n)$desiredExt';
      n++;
    }
    return await File(originalPath).rename(candidate).then((f) => f.path);
  } catch (_) {
    return originalPath;
  }
}
