import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/dio_client.dart';

import '../apis/api.dart';
import '../models/music_model.dart';

class Api implements MusicAPI {
  MusicMetadata? musicMetaData;
  // Reuse a shared streaming service to avoid leaking resources (e.g.,
  // YoutubeExplode instance, connectivity listeners) when Api is created
  // ad-hoc for single calls.
  static final MusicStreamingService _service = MusicStreamingService();

  @override
  Future<String> getDownloadUrl(String videoId) async {
    // 1) Try unified streaming service (with cache + fallback providers)
    try {
      final StreamingData? data = await _service.fetchStreamingData(
        videoId,
        StreamingQuality.medium,
      );
      if (data != null && data.streamUrl != null) {
        musicMetaData = _toMetadata(data);
        return data.streamUrl!;
      }
    } catch (_) {
      // Fall through to HTTP API fallback
    }

    // 2) Fallback to HTTP API using Dio with smart retry (Okatsu)
    try {
      final dio = DioClient.instance;

      final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
      final resp = await dio.get(
        'https://okatsu-rolezapiiz.vercel.app/downloader/ytmp3',
        queryParameters: {'url': youtubeUrl},
        options: Options(
          validateStatus: (s) => true,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118 Safari/537.36',
          },
        ),
      );

      final status = resp.statusCode ?? 0;
      if (status == 200) {
        final dynamic body = resp.data;
        final Map<String, dynamic> jsonResponse = body is String
            ? jsonDecode(body) as Map<String, dynamic>
            : (body as Map<String, dynamic>);
        // Okatsu flat JSON mapping
        if (jsonResponse['status'] == true &&
            jsonResponse['dl'] != null &&
            (jsonResponse['dl'] as String).isNotEmpty) {
          final title = (jsonResponse['title'] as String?) ?? 'Unknown';
          final format = (jsonResponse['format'] as String?) ?? 'mp3';
          final thumb = (jsonResponse['thumb'] as String?) ?? '';
          final dl = (jsonResponse['dl'] as String);
          final duration = (jsonResponse['duration'] as num?)?.toInt() ?? 0;
          final quality = _inferQualityFromUrl(dl) ?? '128';
          final meta = MusicMetadata(
            title: title,
            formart: format,
            thumbnail: thumb,
            downloadUrl: dl,
            videoId: videoId,
            duration: duration,
            quality: quality,
          );
          musicMetaData = meta;
          return dl;
        }
        throw Exception('Invalid Okatsu response');
      } else {
        throw Exception('Failed to fetch stream (status $status)');
      }
    } catch (e) {
      throw Exception('Check your internet connection and try again.');
    }
  }

  @override
  MusicMetadata get getMetadata {
    final meta = musicMetaData;
    if (meta == null) {
      throw StateError('No metadata available. Call getDownloadUrl first.');
    }
    return meta;
  }

  // Map unified StreamingData to legacy MusicMetadata shape
  MusicMetadata _toMetadata(StreamingData d) {
    String qualityStr;
    switch (d.quality) {
      case StreamingQuality.low:
        qualityStr = '128';
        break;
      case StreamingQuality.medium:
        qualityStr = '192';
        break;
      case StreamingQuality.high:
        qualityStr = '320';
        break;
    }

    return MusicMetadata(
      title: d.title.isNotEmpty ? d.title : 'Unknown',
      formart: 'mp3',
      thumbnail: d.thumbnailUrl ?? '',
      downloadUrl: d.streamUrl ?? '',
      videoId: d.videoId,
      duration: d.duration?.inSeconds ?? 0,
      quality: qualityStr,
    );
  }

  void dispose() {
    // Intentionally no-op: _service is shared across Api instances.
    // If you need to dispose at app shutdown, expose a static method
    // (e.g., Api.disposeShared()) and call it from a top-level place.
  }

  String? _inferQualityFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('-320-') ||
        lower.contains('320kb') ||
        lower.contains('320.')) {
      return '320';
    }
    if (lower.contains('-192-') ||
        lower.contains('192kb') ||
        lower.contains('192.')) {
      return '192';
    }
    if (lower.contains('-128-') ||
        lower.contains('128kb') ||
        lower.contains('128.')) {
      return '128';
    }
    return null;
  }
}
