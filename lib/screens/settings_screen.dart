/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautifyv2/blocs/settings/settings_cubit.dart';
import 'package:sautifyv2/blocs/settings/settings_state.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/l10n/strings.dart';
import 'package:sautifyv2/models/streaming_resolver_preference.dart';
import 'package:sautifyv2/screens/equalizer_screen.dart';
import 'package:sautifyv2/services/settings_service.dart';
import 'package:sautifyv2/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final settingsCubit = context.read<SettingsCubit>();
        final locale = state.localeCode;

        if (!state.isReady) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            title: Text(
              AppStrings.settingsTitle(locale),
              style: TextStyle(color: txtcolor, fontWeight: FontWeight.bold),
            ),
          ),
          body: ListTileTheme(
            textColor: txtcolor,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                _sectionHeader('Appearance'),
                _sectionCard(context, [
                  SwitchListTile(
                    value: state.dynamicThemeEnabled,
                    title: const Text('Dynamic Theme'),
                    subtitle:
                        const Text('Use album art colors for the app theme'),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setDynamicThemeEnabled(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<String>(
                    context,
                    title: 'App font',
                    current: state.appFont,
                    items: const [
                      'system',
                      'poppins',
                      'inter',
                      'roboto',
                      'dm_sans',
                      'manrope',
                      'noto_sans',
                    ],
                    itemLabel: (v) {
                      switch (v) {
                        case 'system':
                          return 'System';
                        case 'inter':
                          return 'Inter';
                        case 'roboto':
                          return 'Roboto';
                        case 'dm_sans':
                          return 'DM Sans';
                        case 'manrope':
                          return 'Manrope';
                        case 'noto_sans':
                          return 'Noto Sans';
                        case 'poppins':
                        default:
                          return 'Poppins';
                      }
                    },
                    onChanged: (v) => settingsCubit.setAppFont(v),
                  ),
                ]),
                _tileDivider(),
                _sectionHeader(AppStrings.playback(locale)),
                _sectionCard(context, [
                  _dropdownTile<double>(
                    context,
                    title: AppStrings.playbackSpeed(locale),
                    subtitle: 'Applies to newly started tracks',
                    current: double.parse(
                        state.defaultPlaybackSpeed.toStringAsFixed(2)),
                    items: {
                      ...const [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0],
                      double.parse(
                          state.defaultPlaybackSpeed.toStringAsFixed(2)),
                    }.toList()
                      ..sort(),
                    itemLabel: (v) => '${v.toStringAsFixed(2)}x',
                    onChanged: (v) => settingsCubit.setDefaultPlaybackSpeed(v),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    value: state.defaultShuffle,
                    title: Text(AppStrings.enableShuffleByDefault(locale)),
                    subtitle: Text(AppStrings.shuffleOnStart(locale)),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setDefaultShuffle(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<String>(
                    context,
                    title: AppStrings.loopMode(locale),
                    current: state.defaultLoopMode,
                    items: const ['off', 'one', 'all'],
                    itemLabel: (v) {
                      switch (v) {
                        case 'one':
                          return AppStrings.repeatOne(locale);
                        case 'all':
                          return AppStrings.repeatAll(locale);
                        default:
                          return AppStrings.off(locale);
                      }
                    },
                    onChanged: (v) => settingsCubit.setDefaultLoopMode(v),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    value: state.offlineMode,
                    title: const Text('Offline Mode'),
                    subtitle: const Text('Only play downloaded/local music'),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setOfflineMode(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<double>(
                    context,
                    title: AppStrings.defaultVolume(locale),
                    subtitle: 'New tracks will start at this volume',
                    current: state.defaultVolume,
                    items: {
                      ...const [0.4, 0.6, 0.8, 1.0],
                      state.defaultVolume,
                    }.toList()
                      ..sort(),
                    itemLabel: (v) => '${(v * 100).round()}%',
                    onChanged: (v) => settingsCubit.setDefaultVolume(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<String>(
                    context,
                    title: AppStrings.preferredAudioQuality(locale),
                    subtitle: AppStrings.willApplyToNewTracks(locale),
                    current: state.preferredQuality,
                    items: const ['low', 'medium', 'high'],
                    itemLabel: (v) {
                      switch (v) {
                        case 'low':
                          return AppStrings.lowQuality(locale);
                        case 'high':
                          return AppStrings.highQuality(locale);
                        default:
                          return AppStrings.mediumQuality(locale);
                      }
                    },
                    onChanged: (v) => settingsCubit.setPreferredQuality(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<StreamingResolverPreference>(
                    context,
                    title: 'Streaming source',
                    subtitle: 'Default = API then YTExplode fallback',
                    current: state.streamingResolverPreference,
                    items: StreamingResolverPreference.values,
                    itemLabel: (v) => v.uiLabel,
                    onChanged: (v) {
                      settingsCubit.setStreamingResolverPreference(v);
                      // Keep SettingsService updated too (AudioPlayerService reads it).
                      // ignore: discarded_futures
                      SettingsService()
                          .setStreamingResolverPreference(v)
                          .catchError((_) {});
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    title: const Text('Equalizer'),
                    subtitle:
                        const Text('Adjust audio frequencies (Android only)'),
                    leading: const Icon(Icons.equalizer),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EqualizerScreen(),
                        ),
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    title: Text(AppStrings.crossfadeComingSoon(locale)),
                    subtitle: const Text('Not yet implemented'),
                    trailing: const Icon(Icons.hourglass_empty),
                  ),
                ]),
                _sectionHeader(AppStrings.audioFocus(locale)),
                _sectionCard(context, [
                  SwitchListTile(
                    value: state.duckOnInterruption,
                    title: Text(AppStrings.duckOnInterruption(locale)),
                    subtitle:
                        Text(AppStrings.lowerVolumeOnInterruption(locale)),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setDuckOnInterruption(v),
                  ),
                  _tileDivider(),
                  _dropdownTile<double>(
                    context,
                    title: AppStrings.duckVolume(locale),
                    current: state.duckVolume,
                    items: const [0.2, 0.3, 0.4, 0.5, 0.6],
                    itemLabel: (v) => '${(v * 100).round()}%',
                    onChanged: (v) => settingsCubit.setDuckVolume(v),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    value: state.autoResumeAfterInterruption,
                    title: Text(AppStrings.autoResume(locale)),
                    subtitle:
                        const Text('Resume playback after short focus loss'),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) =>
                        settingsCubit.setAutoResumeAfterInterruption(v),
                  ),
                  _tileDivider(),
                  ListTile(
                    title: const Text('Disable Battery Optimization'),
                    subtitle: const Text(
                      'Prevents playback stopping in background',
                    ),
                    trailing: const Icon(Icons.battery_alert),
                    onTap: () async {
                      final status =
                          await Permission.ignoreBatteryOptimizations.status;
                      if (status.isGranted) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Battery optimization already disabled',
                              ),
                            ),
                          );
                        }
                      } else {
                        await Permission.ignoreBatteryOptimizations.request();
                      }
                    },
                  ),
                ]),
                _sectionHeader('General'),
                _sectionCard(context, [
                  _dropdownTile<String>(
                    context,
                    title: AppStrings.language(locale),
                    current: state.localeCode,
                    items: const ['en', 'sw', 'am'],
                    itemLabel: (v) {
                      switch (v) {
                        case 'sw':
                          return AppStrings.kiswahili(locale);
                        case 'am':
                          return AppStrings.amharic(locale);
                        default:
                          return AppStrings.english(locale);
                      }
                    },
                    onChanged: (v) => settingsCubit.setLocaleCode(v),
                  ),
                ]),
                _sectionHeader('Search'),
                _sectionCard(context, [
                  SwitchListTile(
                    value: state.showRecentSearches,
                    title: const Text('Show recent searches'),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setShowRecentSearches(v),
                  ),
                  _tileDivider(),
                  SwitchListTile(
                    value: state.showSearchSuggestions,
                    title: const Text('Show search suggestions'),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    activeTrackColor:
                        Theme.of(context).colorScheme.primary.withAlpha(140),
                    inactiveThumbColor:
                        Theme.of(context).cardColor.withAlpha(200),
                    inactiveTrackColor:
                        Theme.of(context).cardColor.withAlpha(90),
                    onChanged: (v) => settingsCubit.setShowSearchSuggestions(v),
                  ),
                ]),
                _sectionHeader('Downloads'),
                _sectionCard(context, [
                  ListTile(
                    title: const Text('Download Location'),
                    subtitle: Text(state.downloadPath),
                    trailing: Icon(
                      Icons.edit,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onTap: () => _showPathEditor(context, settingsCubit),
                  ),
                ]),
                _sectionHeader(AppStrings.maintenance(locale)),
                _sectionCard(context, [
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(AppStrings.clearStreamImageCache(locale)),
                    subtitle:
                        Text(AppStrings.fixesBadUrlsAndFreesMemory(locale)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(AppStrings.cacheCleared(locale))),
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: Text(AppStrings.resetAllSettings(locale)),
                    subtitle: Text(AppStrings.resetSettingsDesc(locale)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(AppStrings.resetSettingsQ(locale)),
                          content: Text(AppStrings.resetSettingsDesc(locale)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(AppStrings.reset(locale)),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await settingsCubit.resetToDefaults();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(AppStrings.settingsReset(locale))),
                        );
                      }
                    },
                  ),
                ]),
                _sectionHeader('Updates'),
                _sectionCard(context, [
                  ListTile(
                    leading: const Icon(Icons.system_update_alt_outlined),
                    title: const Text('Check for update'),
                    subtitle: const Text('Tap to query latest GitHub release'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Checking for updates...')),
                      );
                      final info =
                          await UpdateService.instance.checkForUpdate();
                      messenger.hideCurrentSnackBar();
                      if (!info.hasUpdate) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'No updates. Current v${info.currentVersion}.',
                            ),
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Update available: v${info.latestVersion}',
                            ),
                            action: info.htmlUrl == null
                                ? null
                                : SnackBarAction(
                                    label: 'Open',
                                    onPressed: () async {
                                      final uri = Uri.parse(info.htmlUrl!);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                  ),
                          ),
                        );
                      }
                    },
                  ),
                ]),
                _sectionHeader(AppStrings.about(locale)),
                _sectionCard(context, [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(AppStrings.appInfo(locale)),
                    subtitle: Text('Version ${AppStrings.appTitle(locale)}'),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: AppStrings.appTitle(locale),
                        applicationVersion: 'v0.0.3',
                        applicationIcon: const Icon(Icons.library_music),
                        children: const [
                          Text(
                            'A modern music player using YouTube Music & online sources. Open source.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(AppStrings.openSourceLicenses(locale)),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppStrings.appTitle(locale),
                      applicationVersion: 'v0.0.3',
                    ),
                  ),
                ]),
                _sectionHeader(AppStrings.developerSection(locale)),
                _sectionCard(context, [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(AppStrings.developedBy(locale)),
                    subtitle: const Text('Wambugu Kinyua'),
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(AppStrings.contactDeveloper(locale)),
                    subtitle: const Text('wambugukinyua125@gmail.com'),
                    trailing: const Icon(Icons.copy_all_outlined),
                    onTap: () async {
                      final data = const ClipboardData(
                        text: 'wambugukinyua125@gmail.com',
                      );
                      await Clipboard.setData(data);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 60),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: txtcolor.withAlpha(210),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, List<Widget> children) {
    return Card(
      color: Theme.of(context).colorScheme.primary.withAlpha(30),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withAlpha(50),
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _tileDivider() =>
      Divider(height: 1, thickness: 0.6, color: txtcolor.withAlpha(30));

  Widget _dropdownTile<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    required T current,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: txtcolor, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: txtcolor.withAlpha(160), fontSize: 12),
            ),
      trailing: SizedBox(
        width: 160,
        child: DropdownButton<T>(
          isExpanded: true,
          value: current,
          dropdownColor: Theme.of(context).cardColor,
          style: TextStyle(color: txtcolor),
          iconEnabledColor: Theme.of(context).colorScheme.primary,
          underline: const SizedBox.shrink(),
          onChanged: (v) => v == null ? null : onChanged(v),
          items: items
              .map(
                (e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(
                    itemLabel(e),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: txtcolor),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showPathEditor(BuildContext context, SettingsCubit settingsCubit) {
    final controller =
        TextEditingController(text: settingsCubit.state.downloadPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text('Download Location', style: TextStyle(color: txtcolor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: txtcolor),
          decoration: InputDecoration(
            labelText: 'Path',
            labelStyle: TextStyle(color: txtcolor.withAlpha(150)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: txtcolor.withAlpha(100)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: txtcolor)),
          ),
          TextButton(
            onPressed: () {
              settingsCubit.setDownloadPath(controller.text);
              Navigator.pop(context);
            },
            child: Text(
              'Save',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

