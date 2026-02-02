/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

enum StreamingResolverPreference {
  defaultMode,
  apiOnly,
  ytExplodeOnly,
}

extension StreamingResolverPreferencePrefs on StreamingResolverPreference {
  static const String _defaultValue = 'default';

  String get prefValue {
    switch (this) {
      case StreamingResolverPreference.apiOnly:
        return 'api';
      case StreamingResolverPreference.ytExplodeOnly:
        return 'ytexplode';
      case StreamingResolverPreference.defaultMode:
        return _defaultValue;
    }
  }

  static StreamingResolverPreference fromPrefValue(String? value) {
    switch ((value ?? _defaultValue).trim().toLowerCase()) {
      case 'api':
        return StreamingResolverPreference.apiOnly;
      case 'ytexplode':
      case 'yt_explode':
      case 'yt-explode':
        return StreamingResolverPreference.ytExplodeOnly;
      case 'default':
      default:
        return StreamingResolverPreference.defaultMode;
    }
  }

  String get uiLabel {
    switch (this) {
      case StreamingResolverPreference.apiOnly:
        return 'API';
      case StreamingResolverPreference.ytExplodeOnly:
        return 'YTExplode';
      case StreamingResolverPreference.defaultMode:
        return 'Default (API with YTExplode fallback)';
    }
  }
}

