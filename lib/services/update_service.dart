/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String currentVersion; // e.g., 0.0.3
  final String latestVersion; // tag_name without leading v
  final String? htmlUrl; // release page
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.htmlUrl,
    required this.hasUpdate,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _releasesUrl =
      'https://api.github.com/repos/wambugu71/sautify/releases/latest';

  Future<UpdateInfo> checkForUpdate({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Get current app version (strip build number suffix if present)
    String current = '0.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      current = info.version;
    } on MissingPluginException catch (_) {
      // Happens right after hot restart when plugin registry not rebuilt yet;
      // treat as unknown version but never crash.
      if (kDebugMode) {
        debugPrint(
          'package_info_plus not ready (hot restart). Using placeholder version.',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('package_info_plus failed: $e');
      }
    }

    try {
      final res = await http
          .get(
            Uri.parse(_releasesUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'sautifyv2-app',
            },
          )
          .timeout(timeout);

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Update check failed: HTTP ${res.statusCode}');
        }
        return UpdateInfo(
          currentVersion: current,
          latestVersion: current,
          htmlUrl: null,
          hasUpdate: false,
        );
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').trim();
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      final url = data['html_url'] as String?;

      final has = _isNewer(latest, current);
      return UpdateInfo(
        currentVersion: current,
        latestVersion: latest.isEmpty ? current : latest,
        htmlUrl: url,
        hasUpdate: has,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Update check error: $e');
      }
      return UpdateInfo(
        currentVersion: current,
        latestVersion: current,
        htmlUrl: null,
        hasUpdate: false,
      );
    }
  }

  // SemVer compare: returns true if a > b (ignores pre-release/build metadata)
  bool _isNewer(String a, String b) {
    List<int> parse(String v) {
      final core = v.split('-').first;
      final parts = core.split('.');
      int x(int i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;
      return [x(0), x(1), x(2)];
    }

    final aa = parse(a);
    final bb = parse(b);
    for (int i = 0; i < 3; i++) {
      if (aa[i] > bb[i]) return true;
      if (aa[i] < bb[i]) return false;
    }
    return false;
  }
}

