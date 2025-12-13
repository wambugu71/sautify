import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart' as mcu;
import 'package:material_color_utilities/score/score.dart' as mcu;
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/image_cache_service.dart';

class SetColors extends ChangeNotifier {
  List<Color> primaryColors = [bgcolor.withAlpha(200), bgcolor, Colors.black];
  // secondaryColor;
  //get colors
  List<Color> get getPrimaryColors => primaryColors;
  void setColors(List<Color> primary) {
    primaryColors = primary;
    //  secondaryColor = secondary;
    notifyListeners();
  }

  Future<void> getColor(String url) async {
    try {
      // Run directly on main isolate to leverage shared ImageCacheService
      final List<Color> colors = await _updatePaletteFromArtwork(url);
      debugPrint('Colors extracted: $colors');
      primaryColors = colors;
      notifyListeners();
    } catch (e) {
      debugPrint('Error extracting colors: $e');
      primaryColors = [bgcolor.withAlpha(200), bgcolor, Colors.black];
      notifyListeners();
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
      debugPrint('Error in isolate color extraction: $e');
      return <Color>[bgcolor.withAlpha(200), bgcolor, Colors.black];
      // Handle errors if necessary
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
