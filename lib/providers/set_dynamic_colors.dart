/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart' as mcu;
import 'package:material_color_utilities/score/score.dart' as mcu;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

class SetColors extends ChangeNotifier {
  List<Color> primaryColors = [bgcolor.withAlpha(200), bgcolor, Colors.black];

  final Map<String, List<Color>> _urlPaletteCache = <String, List<Color>>{};
  final Map<int, List<Color>> _localPaletteCache = <int, List<Color>>{};
  final Map<String, Future<List<Color>>> _inFlightUrl =
      <String, Future<List<Color>>>{};
  final Map<int, Future<Uint8List?>> _inFlightLocalBytes =
      <int, Future<Uint8List?>>{};

  static final OnAudioQuery _audioQuery = OnAudioQuery();
  // secondaryColor;
  //get colors
  List<Color> get getPrimaryColors => primaryColors;
  void setColors(List<Color> primary) {
    primaryColors = primary;
    //  secondaryColor = secondary;
    notifyListeners();
  }

  Future<void> getColor(String url) async {
    final key = url.trim();
    if (key.isEmpty) return;

    final cached = _urlPaletteCache[key];
    if (cached != null) {
      if (!_samePalette(primaryColors, cached)) {
        primaryColors = cached;
        notifyListeners();
      }
      return;
    }

    try {
      final fut = _inFlightUrl[key] ??= _updatePaletteFromArtwork(key);
      final List<Color> colors = await fut;
      _urlPaletteCache[key] = colors;
      if (kDebugMode) debugPrint('Colors extracted: $colors');

      if (!_samePalette(primaryColors, colors)) {
        primaryColors = colors;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error extracting colors: $e');
      final fallback = <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      if (!_samePalette(primaryColors, fallback)) {
        primaryColors = fallback;
        notifyListeners();
      }
    } finally {
      _inFlightUrl.remove(key);
    }
  }

  Future<void> getColorFromLocalId(int id) async {
    final cached = _localPaletteCache[id];
    if (cached != null) {
      if (!_samePalette(primaryColors, cached)) {
        primaryColors = cached;
        notifyListeners();
      }
      return;
    }

    try {
      final fut = _inFlightLocalBytes[id] ??= _audioQuery.queryArtwork(
        id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        // Only needed for palette extraction; keep smaller to reduce jank.
        size: 256,
        quality: 80,
      );

      final Uint8List? bytes = await fut;

      if (bytes == null || bytes.isEmpty) {
        final fallback = <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
        if (!_samePalette(primaryColors, fallback)) {
          primaryColors = fallback;
          notifyListeners();
        }
        return;
      }

      final colors = await _extractColorsFromBytes(bytes);
      _localPaletteCache[id] = colors;
      if (!_samePalette(primaryColors, colors)) {
        primaryColors = colors;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error extracting colors from local ID: $e');
      final fallback = <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      if (!_samePalette(primaryColors, fallback)) {
        primaryColors = fallback;
        notifyListeners();
      }
    } finally {
      _inFlightLocalBytes.remove(id);
    }
  }

  static bool _samePalette(List<Color> a, List<Color> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value) return false;
    }
    return true;
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
      debugPrint('Error in isolate color extraction: $e');
      return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
    }
  }

  static Future<List<Color>> _extractColorsFromBytes(Uint8List bytes) async {
    try {
      // Slight defer to avoid blocking transition to player screen
      // await Future<void>.delayed(const Duration(milliseconds: 40));

      // Decode with codec at a reduced size for speed (downscale to ~128px longest side)
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
      // Convert RGBA -> ARGB (material_color_utilities expects ARGB int format)
      final pixels = List<int>.generate(raw.length, (i) {
        final v = raw[i];
        final r = v & 0xFF;
        final g = (v >> 8) & 0xFF;
        final b = (v >> 16) & 0xFF;
        final a = (v >> 24) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
      });

      // Quantize colors using material_color_utilities (instance call)
      final quantizerResult = await mcu.QuantizerCelebi().quantize(pixels, 64);
      final ranked = mcu.Score.score(quantizerResult.colorToCount);

      // Extract top colors (fallback chain ensures stability)
      int? primaryArgb = ranked.isNotEmpty ? ranked.first : null;
      int? secondaryArgb = ranked.length > 1 ? ranked[1] : null;

      Color primary = primaryArgb != null
          ? Color(primaryArgb).withOpacity(0.85)
          : const Color(0xFF222222).withOpacity(0.85);
      Color secondary = secondaryArgb != null
          ? Color(secondaryArgb).withOpacity(0.8)
          : const Color(0xFF111111).withOpacity(0.8);

      // Ensure sufficient contrast between first two; if too close, darken second
      if (_relativeLuminance(primary) - _relativeLuminance(secondary) < 0.07) {
        secondary = _darken(secondary, 0.2);
      }

      return <Color>[primary, secondary, Colors.black];
    } catch (e) {
      debugPrint('Error extracting colors from bytes: $e');
      return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
    }
  }

  static Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(resp);
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}
    return null;
  }

  static Color _darken(Color c, double amount) {
    final f = (1 - amount).clamp(0.0, 1.0);
    return Color.fromARGB(
      c.alpha,
      (c.red * f).round(),
      (c.green * f).round(),
      (c.blue * f).round(),
    );
  }

  static double _relativeLuminance(Color c) {
    return 0.2126 * c.red / 255 +
        0.7152 * c.green / 255 +
        0.0722 * c.blue / 255;
  }
}

