/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/l10n/strings.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        if (!settings.isReady) {
          return Scaffold(
            backgroundColor: bgcolor,
            appBar: AppBar(
              title: const Text(
                'Settings',
                style: TextStyle(
                  fontFamily: 'asimovian',
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              backgroundColor: appbarcolor,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final audio = AudioPlayerService();

        return Scaffold(
          backgroundColor: bgcolor,
          appBar: AppBar(
            centerTitle: true,
            title: const Text(
              'Settings',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            backgroundColor: bgcolor,
            foregroundColor: Colors.white,
          ),
          body: Theme(
            data: Theme.of(context).copyWith(
              sliderTheme: SliderTheme.of(context).copyWith(
                activeTrackColor: appbarcolor,
                thumbColor: appbarcolor,
                overlayColor: appbarcolor.withAlpha(48),
                inactiveTrackColor: iconcolor.withAlpha(60),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((s) => appbarcolor),
                trackColor: WidgetStateProperty.resolveWith(
                  (s) => appbarcolor.withAlpha(
                    s.contains(WidgetState.selected) ? 180 : 80,
                  ),
                ),
              ),
              dropdownMenuTheme: DropdownMenuThemeData(
                textStyle: TextStyle(color: txtcolor),
                menuStyle: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(cardcolor),
                ),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.only(
                bottom: 120,
                left: 16,
                right: 16,
                top: 12,
              ),
              children: [
                _sectionHeader(AppStrings.playback(settings.localeCode)),
                _sectionCard([
                  ListTile(
                    leading: Icon(Icons.language, color: appbarcolor),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppStrings.language(settings.localeCode),
                            style: TextStyle(color: txtcolor),
                          ),
                        ),
                        DropdownButton<String>(
                          value: settings.localeCode.split('-').first,
                          dropdownColor: cardcolor,
                          style: TextStyle(color: txtcolor),
                          items: [
                            DropdownMenuItem(
                              value: 'en',
                              child: Text(
                                AppStrings.english(settings.localeCode),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'sw',
                              child: Text(
                                AppStrings.kiswahili(settings.localeCode),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'am',
                              child: Text(
                                AppStrings.amharic(settings.localeCode),
                              ),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await settings.setLocaleCode(v);
                          },
                        ),
                      ],
                    ),
                    subtitle: Text(
                      settings.localeCode.startsWith('sw')
                          ? AppStrings.kiswahili(settings.localeCode)
                          : settings.localeCode.startsWith('am')
                          ? AppStrings.amharic(settings.localeCode)
                          : AppStrings.english(settings.localeCode),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    title: Text(
                      AppStrings.shuffleOnStart(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      AppStrings.enableShuffleByDefault(settings.localeCode),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    value: settings.defaultShuffle,
                    onChanged: (v) async {
                      await settings.setDefaultShuffle(v);
                      await audio.setShuffleModeEnabled(v);
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.repeat, color: appbarcolor),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppStrings.loopMode(settings.localeCode),
                            style: TextStyle(color: txtcolor),
                          ),
                        ),
                        DropdownButton<String>(
                          value: settings.defaultLoopMode,
                          dropdownColor: cardcolor,
                          style: TextStyle(color: txtcolor),
                          items: [
                            DropdownMenuItem(
                              value: 'off',
                              child: Text(AppStrings.off(settings.localeCode)),
                            ),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text(
                                AppStrings.repeatOne(settings.localeCode),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(
                                AppStrings.repeatAll(settings.localeCode),
                              ),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await settings.setDefaultLoopMode(v);
                            switch (v) {
                              case 'one':
                                await audio.setLoopMode(LoopMode.one);
                                break;
                              case 'all':
                                await audio.setLoopMode(LoopMode.all);
                                break;
                              default:
                                await audio.setLoopMode(LoopMode.off);
                            }
                          },
                        ),
                      ],
                    ),
                    subtitle: Text(
                      settings.defaultLoopMode,
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.speed, color: appbarcolor),
                    title: Text(
                      AppStrings.playbackSpeed(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${settings.defaultPlaybackSpeed.toStringAsFixed(2)}x',
                          style: TextStyle(color: txtcolor.withAlpha(160)),
                        ),
                        Slider(
                          value: settings.defaultPlaybackSpeed,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: settings.defaultPlaybackSpeed.toStringAsFixed(
                            2,
                          ),
                          onChanged: (v) async {
                            await settings.setDefaultPlaybackSpeed(v);
                            await audio.setSpeed(v);
                          },
                        ),
                      ],
                    ),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.volume_up, color: appbarcolor),
                    title: Text(
                      AppStrings.defaultVolume(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(settings.defaultVolume * 100).round()}%',
                          style: TextStyle(color: txtcolor.withAlpha(160)),
                        ),
                        Slider(
                          value: settings.defaultVolume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: '${(settings.defaultVolume * 100).round()}%',
                          onChanged: (v) async {
                            await settings.setDefaultVolume(v);
                            await audio.setVolume(v);
                          },
                        ),
                      ],
                    ),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.high_quality, color: appbarcolor),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppStrings.preferredAudioQuality(
                              settings.localeCode,
                            ),
                            style: TextStyle(color: txtcolor),
                          ),
                        ),
                        DropdownButton<String>(
                          value: settings.preferredQuality,
                          dropdownColor: cardcolor,
                          style: TextStyle(color: txtcolor),
                          items: [
                            DropdownMenuItem(
                              value: 'low',
                              child: Text(
                                AppStrings.lowQuality(settings.localeCode),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text(
                                AppStrings.mediumQuality(settings.localeCode),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text(
                                AppStrings.highQuality(settings.localeCode),
                              ),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await settings.setPreferredQuality(v);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppStrings.willApplyToNewTracks(
                                    settings.localeCode,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    subtitle: Text(
                      settings.preferredQuality.toUpperCase(),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.waves_outlined, color: appbarcolor),
                    title: Text(
                      AppStrings.crossfadeComingSoon(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${settings.crossfadeSeconds}s',
                          style: TextStyle(color: txtcolor.withAlpha(160)),
                        ),
                        Slider(
                          value: settings.crossfadeSeconds.toDouble(),
                          min: 0,
                          max: 12,
                          divisions: 12,
                          label: '${settings.crossfadeSeconds}s',
                          onChanged: (v) async {
                            await settings.setCrossfadeSeconds(v.round());
                          },
                        ),
                      ],
                    ),
                  ),
                ]),

                // Search section
                _sectionHeader('Search'),
                _sectionCard([
                  SwitchListTile(
                    title: Text(
                      'Show recent searches',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Display your last queries as chips on the search screen',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    value: settings.showRecentSearches,
                    onChanged: (v) async {
                      await settings.setShowRecentSearches(v);
                    },
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    title: Text(
                      'Show search suggestions',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Fetch and show suggestions while typing in search',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    value: settings.showSearchSuggestions,
                    onChanged: (v) async {
                      await settings.setShowSearchSuggestions(v);
                      // UI will react in SearchOverlay; nothing else to do here
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.history, color: appbarcolor),
                    title: Text(
                      'Clear recent searches',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Remove all stored search queries',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    onTap: () async {
                      // Clear the SharedPreferences key used by SearchOverlay
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('recent_searches');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Recent searches cleared'),
                          ),
                        );
                      }
                    },
                  ),
                ]),

                _sectionHeader(AppStrings.audioFocus(settings.localeCode)),
                _sectionCard([
                  SwitchListTile(
                    title: Text(
                      AppStrings.duckOnInterruption(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      AppStrings.lowerVolumeOnInterruption(settings.localeCode),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    value: settings.duckOnInterruption,
                    onChanged: (v) async {
                      await settings.setDuckOnInterruption(v);
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.volume_down_alt, color: appbarcolor),
                    title: Text(
                      AppStrings.duckVolume(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(settings.duckVolume * 100).round()}%',
                          style: TextStyle(color: txtcolor.withAlpha(160)),
                        ),
                        Slider(
                          value: settings.duckVolume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: '${(settings.duckVolume * 100).round()}%',
                          onChanged: settings.duckOnInterruption
                              ? (v) async {
                                  await settings.setDuckVolume(v);
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    title: Text(
                      AppStrings.autoResume(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    value: settings.autoResumeAfterInterruption,
                    onChanged: (v) async {
                      await settings.setAutoResumeAfterInterruption(v);
                    },
                  ),
                ]),

                _sectionHeader(AppStrings.maintenance(settings.localeCode)),
                _sectionCard([
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services_outlined,
                      color: appbarcolor,
                    ),
                    title: Text(
                      AppStrings.clearStreamImageCache(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      AppStrings.fixesBadUrlsAndFreesMemory(
                        settings.localeCode,
                      ),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    trailing: _primaryChip(
                      AppStrings.clear(settings.localeCode),
                    ),
                    onTap: () {
                      AudioPlayerService().clearCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppStrings.cacheCleared(settings.localeCode),
                          ),
                        ),
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.refresh_outlined, color: appbarcolor),
                    title: Text(
                      AppStrings.resetAllSettings(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    trailing: _primaryChip(
                      AppStrings.reset(settings.localeCode),
                    ),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: cardcolor,
                          title: Text(
                            AppStrings.resetSettingsQ(settings.localeCode),
                            style: TextStyle(color: txtcolor),
                          ),
                          content: Text(
                            AppStrings.resetSettingsDesc(settings.localeCode),
                            style: TextStyle(color: txtcolor.withAlpha(180)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(AppStrings.off(settings.localeCode)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appbarcolor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                AppStrings.reset(settings.localeCode),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await settings.resetToDefaults();
                        try {
                          await audio.setSpeed(settings.defaultPlaybackSpeed);
                        } catch (_) {}
                        try {
                          await audio.setVolume(settings.defaultVolume);
                        } catch (_) {}
                        await audio.setShuffleModeEnabled(
                          settings.defaultShuffle,
                        );
                        switch (settings.defaultLoopMode) {
                          case 'one':
                            await audio.setLoopMode(LoopMode.one);
                            break;
                          case 'all':
                            await audio.setLoopMode(LoopMode.all);
                            break;
                          default:
                            await audio.setLoopMode(LoopMode.off);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.settingsReset(settings.localeCode),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ]),

                _sectionHeader(AppStrings.about(settings.localeCode)),
                _sectionCard([
                  ListTile(
                    leading: Icon(Icons.info_outline, color: appbarcolor),
                    title: Text(
                      AppStrings.appInfo(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Sautify v0.0.2',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: AppStrings.appTitle(
                          settings.localeCode,
                        ),
                        applicationVersion: '0.0.2',
                        applicationIcon: const Icon(Icons.library_music),
                        barrierColor: bgcolor.withAlpha(200),
                        children: const [
                          Text(
                            'A modern music streaming player backed  by youtube music client and online sources.',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'roboto',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(
                      Icons.privacy_tip_outlined,
                      color: appbarcolor,
                    ),
                    title: Text(
                      AppStrings.privacyAndPermissions(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      AppStrings.notificationsStorageNetwork(
                        settings.localeCode,
                      ),
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    onTap: () {},
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.article_outlined, color: appbarcolor),
                    title: Text(
                      AppStrings.openSourceLicenses(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: AppStrings.appTitle(
                          settings.localeCode,
                        ),
                        applicationVersion: '0.0.2',
                      );
                    },
                  ),
                ]),

                _sectionHeader(
                  AppStrings.developerSection(settings.localeCode),
                ),
                _sectionCard([
                  ListTile(
                    leading: Icon(Icons.person_outline, color: appbarcolor),
                    title: Text(
                      AppStrings.developedBy(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Wambugu Kinyua',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.email_outlined, color: appbarcolor),
                    title: Text(
                      AppStrings.contactDeveloper(settings.localeCode),
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'wambugukinyua125@gmail.com',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    trailing: _primaryChip(
                      AppStrings.copy(settings.localeCode),
                    ),
                    onTap: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: 'wambugukinyua125@gmail.com'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppStrings.copiedToClipboard(settings.localeCode),
                          ),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: txtcolor,
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Card(
      color: cardcolor,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      ),
    );
  }

  Widget _tileDivider() =>
      Divider(height: 1, color: Colors.white.withAlpha(20));

  Widget _primaryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: appbarcolor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
