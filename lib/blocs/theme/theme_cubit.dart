/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart' as mcu;
import 'package:material_color_utilities/score/score.dart' as mcu;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

import 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(ThemeState.initial());

  static List<Color> _ensureMinGradientColors(List<Color> colors) {
    if (colors.length >= 2) return colors;
    if (colors.isEmpty) {
      return <Color>[bgcolor.withAlpha(200), bgcolor];
    }
    final c = colors.first;
    return <Color>[c, c];
  }

  void setColors(List<Color> primary) {
    emit(state.copyWith(primaryColors: _ensureMinGradientColors(primary)));
  }

  Future<void> getColor(String url) async {
    try {
      final List<Color> colors = await _updatePaletteFromArtwork(url);
      emit(state.copyWith(primaryColors: _ensureMinGradientColors(colors)));
    } catch (e) {
      emit(ThemeState.initial());
    }
  }

  Future<void> getColorFromLocalId(int id) async {
    try {
      final OnAudioQuery audioQuery = OnAudioQuery();
      final bytes = await audioQuery.queryArtwork(
        id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 1000,
        quality: 100,
      );

      if (bytes == null || bytes.isEmpty) {
        emit(ThemeState.initial());
        return;
      }

      final colors = await _extractColorsFromBytes(bytes);
      emit(state.copyWith(primaryColors: _ensureMinGradientColors(colors)));
    } catch (e) {
      emit(ThemeState.initial());
    }
  }

  static Future<List<Color>> _updatePaletteFromArtwork(String url) async {
    try {
      final cache = ImageCacheService();
      final bytes =
          await cache.getCachedImage(url) ?? await _fetchImageBytes(url);
      if (bytes == null || bytes.isEmpty) {
        return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      }
      return await _extractColorsFromBytes(bytes);
    } catch (e) {
      return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
    }
  }

  static Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      return await consolidateHttpClientResponseBytes(response);
    } catch (e) {
      return null;
    }
  }

  static Future<List<Color>> _extractColorsFromBytes(Uint8List bytes) async {
    try {
      final codec = await instantiateImageCodec(
        bytes,
        targetHeight: 128,
        targetWidth: 128,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) {
        return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      }
      final raw = byteData.buffer.asUint32List();
      final pixels = List<int>.generate(raw.length, (i) {
        final v = raw[i];
        final r = v & 0xFF;
        final g = (v >> 8) & 0xFF;
        final b = (v >> 16) & 0xFF;
        final a = (v >> 24) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
      });

      final result = await mcu.QuantizerCelebi().quantize(pixels, 128);
      final scored = mcu.Score.score(result.colorToCount);
      final top = scored.take(3).toList();

      if (top.isEmpty) {
        return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      }

      return _ensureMinGradientColors(top.map((c) => Color(c)).toList());
    } catch (e) {
      return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
    }
  }
}

