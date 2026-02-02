/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/audio_player_service.dart';

class WidgetService {
  static final WidgetService _instance = WidgetService._internal();
  factory WidgetService() => _instance;
  WidgetService._internal();

  static const String _widgetProvider = 'MusicWidget';

  final AudioPlayerService _audioService = AudioPlayerService();
  StreamSubscription? _trackSubscription;
  StreamSubscription? _playerStateSubscription;

  void init() {
    // Listen to track changes
    _trackSubscription = _audioService.currentTrackStream.listen((track) {
      _updateWidget(track, isPlaying: _audioService.player.playing);
    });

    // Listen to player state changes
    _playerStateSubscription = _audioService.player.playerStateStream.listen((
      state,
    ) {
      _updateWidget(_audioService.currentTrack, isPlaying: state.playing);
    });
  }

  Future<void> _updateWidget(
    StreamingData? track, {
    bool isPlaying = false,
  }) async {
    // Save data
    await HomeWidget.saveWidgetData<String>(
      'widget_title',
      track?.title ?? 'No Song',
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_artist',
      track?.artist ?? 'Unknown Artist',
    );
    await HomeWidget.saveWidgetData<bool>('widget_is_playing', isPlaying);

    if (track?.thumbnailUrl != null) {
      final path = await _downloadAndSaveImage(track!.thumbnailUrl!);
      if (path != null) {
        await HomeWidget.saveWidgetData<String>('widget_image_path', path);
      }
    } else {
      await HomeWidget.saveWidgetData<String>('widget_image_path', null);
    }

    await HomeWidget.updateWidget(
      name: _widgetProvider,
      androidName: _widgetProvider,
      qualifiedAndroidName: 'com.sautify.player.MusicWidget',
    );
  }

  Future<String?> _downloadAndSaveImage(String url) async {
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/widget_cover.png';
      final file = File(path);

      // Check if we already have it? Maybe not worth the complexity for now.
      // Just download.
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return path;
      }
    } catch (e) {
      debugPrint('Error downloading widget image: $e');
    }
    return null;
  }

  void dispose() {
    _trackSubscription?.cancel();
    _playerStateSubscription?.cancel();
  }
}

