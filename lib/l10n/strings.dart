/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:ui' show Locale;

class AppStrings {
  static const supportedLocales = [Locale('en'), Locale('sw'), Locale('am')];

  static String _codeOrEn(String? code) {
    if (code == null || code.isEmpty) return 'en';
    final lang = code.split('-').first.toLowerCase();
    return _values.containsKey(lang) ? lang : 'en';
  }

  // Common
  static String appTitle(String? code) => _t(code, 'appTitle');
  static String homeTitle(String? code) => _t(code, 'homeTitle');
  static String libraryTitle(String? code) => _t(code, 'libraryTitle');
  static String settingsTitle(String? code) => _t(code, 'settingsTitle');

  // Settings screen
  static String playback(String? code) => _t(code, 'playback');
  static String audioFocus(String? code) => _t(code, 'audioFocus');
  static String maintenance(String? code) => _t(code, 'maintenance');
  static String about(String? code) => _t(code, 'about');
  static String shuffleOnStart(String? code) => _t(code, 'shuffleOnStart');
  static String enableShuffleByDefault(String? code) =>
      _t(code, 'enableShuffleByDefault');
  static String loopMode(String? code) => _t(code, 'loopMode');
  static String off(String? code) => _t(code, 'off');
  static String repeatOne(String? code) => _t(code, 'repeatOne');
  static String repeatAll(String? code) => _t(code, 'repeatAll');
  static String playbackSpeed(String? code) => _t(code, 'playbackSpeed');
  static String defaultVolume(String? code) => _t(code, 'defaultVolume');
  static String preferredAudioQuality(String? code) =>
      _t(code, 'preferredAudioQuality');
  static String lowQuality(String? code) => _t(code, 'lowQuality');
  static String mediumQuality(String? code) => _t(code, 'mediumQuality');
  static String highQuality(String? code) => _t(code, 'highQuality');
  static String willApplyToNewTracks(String? code) =>
      _t(code, 'willApplyToNewTracks');
  static String crossfadeComingSoon(String? code) =>
      _t(code, 'crossfadeComingSoon');
  static String duckOnInterruption(String? code) =>
      _t(code, 'duckOnInterruption');
  static String lowerVolumeOnInterruption(String? code) =>
      _t(code, 'lowerVolumeOnInterruption');
  static String duckVolume(String? code) => _t(code, 'duckVolume');
  static String autoResume(String? code) => _t(code, 'autoResume');
  static String clearStreamImageCache(String? code) =>
      _t(code, 'clearStreamImageCache');
  static String fixesBadUrlsAndFreesMemory(String? code) =>
      _t(code, 'fixesBadUrlsAndFreesMemory');
  static String clear(String? code) => _t(code, 'clear');
  static String resetAllSettings(String? code) => _t(code, 'resetAllSettings');
  static String reset(String? code) => _t(code, 'reset');
  static String resetSettingsQ(String? code) => _t(code, 'resetSettingsQ');
  static String resetSettingsDesc(String? code) =>
      _t(code, 'resetSettingsDesc');
  static String appInfo(String? code) => _t(code, 'appInfo');
  static String privacyAndPermissions(String? code) =>
      _t(code, 'privacyAndPermissions');
  static String notificationsStorageNetwork(String? code) =>
      _t(code, 'notificationsStorageNetwork');
  static String openSourceLicenses(String? code) =>
      _t(code, 'openSourceLicenses');
  static String language(String? code) => _t(code, 'language');
  static String english(String? code) => _t(code, 'english');
  static String kiswahili(String? code) => _t(code, 'kiswahili');
  static String amharic(String? code) => _t(code, 'amharic');
  static String cacheCleared(String? code) => _t(code, 'cacheCleared');
  static String settingsReset(String? code) => _t(code, 'settingsReset');
  // Developer section
  static String developerSection(String? code) => _t(code, 'developer');
  static String developedBy(String? code) => _t(code, 'developedBy');
  static String contactDeveloper(String? code) => _t(code, 'contactDeveloper');
  static String email(String? code) => _t(code, 'email');
  static String copy(String? code) => _t(code, 'copy');
  static String copiedToClipboard(String? code) =>
      _t(code, 'copiedToClipboard');

  // Library screen
  static String recentlyPlayed(String? code) => _t(code, 'recentlyPlayed');
  static String noRecents(String? code) => _t(code, 'noRecents');
  static String favorites(String? code) => _t(code, 'favorites');
  static String noFavorites(String? code) => _t(code, 'noFavorites');
  static String playlists(String? code) => _t(code, 'playlists');
  static String noPlaylists(String? code) => _t(code, 'noPlaylists');
  static String albums(String? code) => _t(code, 'albums');
  static String noAlbums(String? code) => _t(code, 'noAlbums');
  static String downloads(String? code) => _t(code, 'downloads');
  static String noDownloads(String? code) => _t(code, 'noDownloads');
  static String playAll(String? code) => _t(code, 'playAll');
  static String recentChip(String? code) => _t(code, 'recentChip');
  static String favoriteChip(String? code) => _t(code, 'favoriteChip');
  static String playlistChip(String? code) => _t(code, 'playlistChip');
  static String albumChip(String? code) => _t(code, 'albumChip');
  static String offlineChip(String? code) => _t(code, 'offlineChip');
  static String likedSongs(String? code) => _t(code, 'likedSongs');
  static String allPlaylists(String? code) => _t(code, 'allPlaylists');
  static String allAlbums(String? code) => _t(code, 'allAlbums');
  static String tracksCount(String? code, int count) {
    final lang = _codeOrEn(code);
    final word = lang == 'sw' ? 'nyimbo' : 'tracks';
    return '$count $word';
  }

  static String _t(String? code, String key) {
    final lang = _codeOrEn(code);
    return _values[lang]![key] ?? key;
  }

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'appTitle': 'Sautify',
      'homeTitle': 'Home',
      'libraryTitle': 'Library',
      'settingsTitle': 'Settings',
      // Settings
      'playback': 'Playback',
      'audioFocus': 'Audio Focus & Interruptions',
      'maintenance': 'Maintenance',
      'about': 'About',
      'shuffleOnStart': 'Shuffle on start',
      'enableShuffleByDefault': 'Enable shuffle by default',
      'loopMode': 'Loop mode',
      'off': 'Off',
      'repeatOne': 'Repeat one',
      'repeatAll': 'Repeat all',
      'playbackSpeed': 'Playback speed',
      'defaultVolume': 'Default volume',
      'preferredAudioQuality': 'Preferred audio quality',
      'lowQuality': 'Low (64-128 kbps)',
      'mediumQuality': 'Medium (128-192 kbps)',
      'highQuality': 'High (256-320 kbps)',
      'willApplyToNewTracks': 'Quality will apply to new tracks',
      'crossfadeComingSoon': 'Crossfade (coming soon)',
      'duckOnInterruption': 'Duck on interruption',
      'lowerVolumeOnInterruption': 'Lower volume on transient interruptions',
      'duckVolume': 'Duck volume',
      'autoResume': 'Auto-resume after interruption',
      'clearStreamImageCache': 'Clear stream/image cache',
      'fixesBadUrlsAndFreesMemory': 'Fixes bad URLs and frees memory',
      'clear': 'Clear',
      'resetAllSettings': 'Reset all settings',
      'reset': 'Reset',
      'resetSettingsQ': 'Reset settings?',
      'resetSettingsDesc':
          'This will restore default playback and audio focus settings.',
      'appInfo': 'App info',
      'privacyAndPermissions': 'Privacy & permissions',
      'notificationsStorageNetwork': 'Notifications, storage, network',
      'openSourceLicenses': 'Open source licenses',
      'language': 'Language',
      'english': 'English',
      'kiswahili': 'Kiswahili',
      'amharic': 'Amharic',
      'cacheCleared': 'Cache cleared',
      'settingsReset': 'Settings reset',
      // Developer
      'developer': 'Developer',
      'developedBy': 'Developed by',
      'contactDeveloper': 'Contact developer',
      'email': 'Email',
      'copy': 'Copy',
      'copiedToClipboard': 'Copied to clipboard',
      // Library
      'recentlyPlayed': 'Recently Played',
      'noRecents': 'No recents',
      'favorites': 'Favorites',
      'noFavorites': 'No favorites',
      'playlists': 'Playlists',
      'noPlaylists': 'No playlists',
      'albums': 'Albums',
      'noAlbums': 'No albums',
      'downloads': 'Downloads',
      'noDownloads': 'No downloads',
      'playAll': 'Play all',
      'recentChip': 'RECENT',
      'favoriteChip': 'FAVORITE',
      'playlistChip': 'PLAYLIST',
      'albumChip': 'ALBUM',
      'offlineChip': 'OFFLINE',
      'likedSongs': 'Liked Songs',
      'allPlaylists': 'All Playlists',
      'allAlbums': 'All Albums',
    },
    'sw': {
      'appTitle': 'Sautify',
      'homeTitle': 'Nyumbani',
      'libraryTitle': 'Maktaba',
      'settingsTitle': 'Mipangilio',
      // Settings
      'playback': 'Uchezaji',
      'audioFocus': 'Umakini wa Sauti na Mikatizo',
      'maintenance': 'Matengenezo',
      'about': 'Kuhusu',
      'shuffleOnStart': 'Changanya unapoanza',
      'enableShuffleByDefault': 'Washa kuchanganya kimyakimya',
      'loopMode': 'Hali ya kurudia',
      'off': 'Zima',
      'repeatOne': 'Rudia wimbo mmoja',
      'repeatAll': 'Rudia yote',
      'playbackSpeed': 'Mwendo wa uchezaji',
      'defaultVolume': 'Sauti chaguo-msingi',
      'preferredAudioQuality': 'Ubora wa sauti unaopendekezwa',
      'lowQuality': 'Chini (64-128 kbps)',
      'mediumQuality': 'Wastani (128-192 kbps)',
      'highQuality': 'Juu (256-320 kbps)',
      'willApplyToNewTracks': 'Ubora utatumika kwa nyimbo mpya',
      'crossfadeComingSoon': 'Mchanganyiko wa mpito (hivi karibuni)',
      'duckOnInterruption': 'Punguza sauti wakati wa kero',
      'lowerVolumeOnInterruption':
          'Punguza sauti wakati wa mikatizo ya muda mfupi',
      'duckVolume': 'Kiwango cha kupunguza sauti',
      'autoResume': 'Anza upya kiotomatiki baada ya kero',
      'clearStreamImageCache': 'Futa kumbukumbu ya mito/picha',
      'fixesBadUrlsAndFreesMemory':
          'Inarekebisha URL mbovu na kuachia kumbukumbu',
      'clear': 'Futa',
      'resetAllSettings': 'Weka upya mipangilio yote',
      'reset': 'Weka upya',
      'resetSettingsQ': 'Uweke upya mipangilio?',
      'resetSettingsDesc':
          'Hii itarejesha mipangilio chaguo-msingi ya uchezaji na makini ya sauti.',
      'appInfo': 'Maelezo ya programu',
      'privacyAndPermissions': 'Faragha na ruhusa',
      'notificationsStorageNetwork': 'Arifa, hifadhi, mtandao',
      'openSourceLicenses': 'Leseni za chanzo huria',
      'language': 'Lugha',
      'english': 'Kiingereza',
      'kiswahili': 'Kiswahili',
      'amharic': 'Amharic',
      'cacheCleared': 'Kache imefutwa',
      'settingsReset': 'Mipangilio imewekwa upya',
      // Developer
      'developer': 'Msanidi',
      'developedBy': 'Imetengenezwa na',
      'contactDeveloper': 'Wasiliana na msanidi',
      'email': 'Barua pepe',
      'copy': 'Nakili',
      'copiedToClipboard': 'Imenakiliwa kwenye ubao wa kunakili',
      // Library
      'recentlyPlayed': 'Zilizosikiwa Karibuni',
      'noRecents': 'Hakuna za hivi karibuni',
      'favorites': 'Vipendwa',
      'noFavorites': 'Hakuna vipendwa',
      'playlists': 'Orodha za nyimbo',
      'noPlaylists': 'Hakuna orodha za nyimbo',
      'albums': 'Albamu',
      'noAlbums': 'Hakuna albamu',
      'downloads': 'Vipakuliwa',
      'noDownloads': 'Hakuna vipakuliwa',
      'playAll': 'Cheza zote',
      'recentChip': 'HIVI KARIBUNI',
      'favoriteChip': 'KIPENDWA',
      'playlistChip': 'ORODHA',
      'albumChip': 'ALBAMU',
      'offlineChip': 'NJE YA MTANDAO',
      'likedSongs': 'Nyimbo Uzipendazo',
      'allPlaylists': 'Orodha Zote',
      'allAlbums': 'Albamu Zote',
    },
    // Amharic
    'am': {
      'appTitle': 'áˆ³á‹á‰²á‹á‹­',
      'homeTitle': 'áˆ˜áŠáˆ»',
      'libraryTitle': 'á‰¤á‰°-áˆ˜áŒ½áˆáá‰µ',
      'settingsTitle': 'á‰…áŠ•á‰¥áˆ®á‰½',
      'playback': 'áˆ›áŒ«á‹ˆá‰µ',
      'audioFocus': 'á‹¨á‹µáˆáŒ½ á‰µáŠ©áˆ¨á‰µ áŠ¥áŠ“ áˆ›á‰‹áˆ¨áŒ¦á‰½',
      'maintenance': 'áŒ¥áŒˆáŠ“',
      'about': 'áˆµáˆˆ',
      'shuffleOnStart': 'á‰ áˆ˜áŒ€áˆ˜áˆ­á‹« áˆ‹á‹­ áˆ˜áˆˆá‹‹á‹ˆáŒ¥',
      'enableShuffleByDefault': 'á‰ áŠá‰£áˆªáŠá‰µ áˆ˜áˆˆá‹‹á‹ˆáŒ¥áŠ• áŠ áŠ•á‰ƒ',
      'loopMode': 'á‹¨á‹µáŒáŒáˆžáˆ½ áˆáŠá‰³',
      'off': 'áŠ áŒ¥á‹',
      'repeatOne': 'áŠ áŠ•á‹µ á‹µáŒˆáˆ',
      'repeatAll': 'áˆáˆ‰áŠ•áˆ á‹µáŒˆáˆ',
      'playbackSpeed': 'á‹¨áˆ›áŒ«á‹ˆá‰µ ááŒ¥áŠá‰µ',
      'defaultVolume': 'áŠá‰£áˆª á‹µáˆáŒ½',
      'preferredAudioQuality': 'á‹¨á‰°áˆ˜áˆ¨áŒ  á‹¨á‹µáˆáŒ½ áŒ¥áˆ«á‰µ',
      'lowQuality': 'á‹á‰…á‰°áŠ› (64-128 áŠªá‰£á’áŠ¤áˆµ)',
      'mediumQuality': 'áˆ˜áŠ«áŠ¨áˆˆáŠ› (128-192 áŠªá‰£á’áŠ¤áˆµ)',
      'highQuality': 'áŠ¨áá‰°áŠ› (256-320 áŠªá‰£á’áŠ¤áˆµ)',
      'willApplyToNewTracks': 'áŒ¥áˆ«á‰± áˆˆáŠ á‹²áˆµ á‰µáˆ«áŠ®á‰½ á‰°áŒá‰£áˆ«á‹Š á‹­áˆ†áŠ“áˆ',
      'crossfadeComingSoon': 'áŠ­áˆ®áˆµáŒá‹µ (á‰ á‰…áˆ­á‰¡ á‹­áˆ˜áŒ£áˆ)',
      'duckOnInterruption': 'á‰ áˆ›á‰‹áˆ¨áŒ¥ áˆ‹á‹­ á‹µáˆáŒ½ á‰…áŠ•áˆµ',
      'lowerVolumeOnInterruption': 'á‰ áŒŠá‹œá‹«á‹Š áˆ›á‰‹áˆ¨áŒ¦á‰½ áˆ‹á‹­ á‹µáˆáŒ½ á‰€áŠ•áˆµ',
      'duckVolume': 'á‹¨á‹µáˆáŒ½ á‰…áŠ•áˆµ',
      'autoResume': 'áŠ¨áˆ›á‰‹áˆ¨áŒ¥ á‰ áŠ‹áˆ‹ á‰ áˆ«áˆµ-áˆ°áˆ­ á‰€áŒ¥áˆ',
      'clearStreamImageCache': 'á‹¨á‹¥áˆ¨á‰µ/áˆáˆµáˆ áˆ˜áˆ¸áŒŽáŒ« áŠ áŒ½á‹³',
      'fixesBadUrlsAndFreesMemory':
          'áˆ˜áŒ¥áŽ á‹©áŠ áˆ­áŠ¤áˆŽá‰½áŠ• á‹«áˆµá‰°áŠ«áŠ­áˆ‹áˆ áŠ¥áŠ“ áˆ›áˆ…á‹°áˆ¨ á‰µá‹áˆµá‰³áŠ• áŠáŒ» á‹«á‹°áˆ­áŒ‹áˆ',
      'clear': 'áŠ áŒ½á‹³',
      'resetAllSettings': 'áˆáˆ‰áŠ•áˆ á‰…áŠ•á‰¥áˆ®á‰½ á‹³áŒáˆ áŠ áˆµáŒ€áˆáˆ­',
      'reset': 'á‹³áŒáˆ áŠ áˆµáŒ€áˆáˆ­',
      'resetSettingsQ': 'á‰…áŠ•á‰¥áˆ®á‰½áŠ• á‹³áŒáˆ áŠ áˆµáŒ€áˆáˆ­?',
      'resetSettingsDesc': 'á‹­áˆ… áŠá‰£áˆª á‹¨áˆ›áŒ«á‹ˆá‰µ áŠ¥áŠ“ á‹¨á‹µáˆáŒ½ á‰µáŠ©áˆ¨á‰µ á‰…áŠ•á‰¥áˆ®á‰½áŠ• á‹­áˆ˜áˆáˆ³áˆ.',
      'appInfo': 'á‹¨áˆ˜á‰°áŒá‰ áˆªá‹« áˆ˜áˆ¨áŒƒ',
      'privacyAndPermissions': 'áŒáˆ‹á‹ŠáŠá‰µ áŠ¥áŠ“ áá‰ƒá‹¶á‰½',
      'notificationsStorageNetwork': 'áˆ›áˆ³á‹ˆá‰‚á‹«á‹Žá‰½á£ áˆ›áŠ¨áˆ›á‰»á£ áŠ á‹á‰³áˆ¨ áˆ˜áˆ¨á‰¥',
      'openSourceLicenses': 'á‹¨áŠ­áá‰µ áˆáŠ•áŒ­ áá‰ƒá‹¶á‰½',
      'language': 'á‰‹áŠ•á‰‹',
      'english': 'áŠ¥áŠ•áŒáˆŠá‹áŠ›',
      'kiswahili': 'áŠªáˆµá‹‹áˆ‚áˆŠ',
      'amharic': 'áŠ áˆ›áˆ­áŠ›',
      'cacheCleared': 'áˆ˜áˆ¸áŒŽáŒ« á‰°áŒ¸á‹³',
      'settingsReset': 'á‰…áŠ•á‰¥áˆ®á‰½ á‹³áŒáˆ á‰°áŒ€áˆ˜áˆ©',
      'developer': 'áŒˆáŠ•á‰¢',
      'developedBy': 'á‹¨á‰°áŒˆáŠá‰£á‹ á‰ ',
      'contactDeveloper': 'áŒˆáŠ•á‰¢áŠ• á‹«áŒáŠ™',
      'email': 'áŠ¢áˆœá‹­áˆ',
      'copy': 'á‰…á‹³',
      'copiedToClipboard': 'á‹ˆá‹° á‰…áŠ•áŒ¥á‰¥ áˆ°áˆŒá‹³ á‰°á‰€á‹µá‰·áˆá¢',
      'recentlyPlayed': 'á‰ á‰…áˆ­á‰¥ á‹¨á‰°áŒ«á‹ˆá‰±',
      'noRecents': 'á‰ á‰…áˆ­á‰¥ á‹¨á‰°áŒ«á‹ˆá‰± á‹¨áˆ‰áˆ',
      'favorites': 'á‰°á‹ˆá‹³áŒ†á‰½',
      'noFavorites': 'á‰°á‹ˆá‹³áŒ†á‰½ á‹¨áˆ‰áˆ',
      'playlists': 'áŠ áŒ«á‹‹á‰½ á‹áˆ­á‹áˆ®á‰½',
      'noPlaylists': 'áŠ áŒ«á‹‹á‰½ á‹áˆ­á‹áˆ®á‰½ á‹¨áˆ‰áˆ',
      'albums': 'áŠ áˆá‰ áˆžá‰½',
      'noAlbums': 'áŠ áˆá‰ áˆžá‰½ á‹¨áˆ‰áˆ',
      'downloads': 'á‹¨á‹ˆáˆ¨á‹±',
      'noDownloads': 'á‹¨á‹ˆáˆ¨á‹± á‹¨áˆ‰áˆ',
      'playAll': 'áˆáˆ‰áŠ•áˆ áŠ áŒ«á‹á‰µ',
      'recentChip': 'á‰ á‰…áˆ­á‰¥',
      'favoriteChip': 'á‰°á‹ˆá‹³áŒ…',
      'playlistChip': 'áŠ áŒ«á‹‹á‰½ á‹áˆ­á‹áˆ­',
      'albumChip': 'áŠ áˆá‰ áˆ',
      'offlineChip': 'áŠ¨áˆ˜áˆµáˆ˜áˆ­ á‹áŒª',
      'likedSongs': 'á‹¨á‰°á‹ˆá‹°á‹± á‹˜áˆáŠ–á‰½',
      'allPlaylists': 'áˆáˆ‰áˆ áŠ áŒ«á‹‹á‰½ á‹áˆ­á‹áˆ®á‰½',
      'allAlbums': 'áˆáˆ‰áˆ áŠ áˆá‰ áˆžá‰½',
    },
  };
}

