import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import '../apis/api.dart';
import '../models/music_model.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class Api implements MusicAPI {
  MusicMetadata? musicMetaData;
  final MusicStreamingService _service = MusicStreamingService();

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

    // 2) Fallback to HTTP API with retry/timeout
    try {
      final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
      final musicData = await retry(
        () => http
            .get(
              Uri.parse(
                'https://apis-keith.vercel.app/download/dlmp3?url=$youtubeUrl',
              ),
            )
            .timeout(const Duration(seconds: 10)),
        retryIf: (e) => e is TimeoutException || e is http.ClientException,
        maxAttempts: 3,
        delayFactor: const Duration(seconds: 3),
      );

      if (musicData.statusCode == 200) {
        final jsonResponse = jsonDecode(musicData.body);
        final meta = MusicMetadata.fromJson(jsonResponse);
        musicMetaData = meta;
        return meta.downloadUrl;
      } else {
        throw Exception(
          'Failed to fetch stream (status ${musicData.statusCode})',
        );
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
    _service.dispose();
  }
}
