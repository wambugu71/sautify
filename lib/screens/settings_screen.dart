import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/l10n/strings.dart';
import 'package:sautifyv2/screens/equalizer_screen.dart';
import 'package:sautifyv2/services/settings_service.dart';
import 'package:sautifyv2/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final locale = settings.localeCode;

    if (!settings.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: bgcolor,
      appBar: AppBar(
        backgroundColor: bgcolor,
        elevation: 0,
        title: Text(
          AppStrings.settingsTitle(locale),
          style: TextStyle(color: txtcolor, fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(color: iconcolor),
      ),
      body: ListTileTheme(
        iconColor: appbarcolor,
        textColor: txtcolor,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            _sectionHeader(AppStrings.playback(locale)),
            _sectionCard([
              _dropdownTile<double>(
                context,
                title: AppStrings.playbackSpeed(locale),
                subtitle: 'Applies to newly started tracks',
                current: settings.defaultPlaybackSpeed,
                items: const [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0],
                itemLabel: (v) => '${v}x',
                onChanged: (v) => settings.setDefaultPlaybackSpeed(v),
              ),
              _tileDivider(),
              SwitchListTile(
                value: settings.defaultShuffle,
                title: Text(AppStrings.enableShuffleByDefault(locale)),
                subtitle: Text(AppStrings.shuffleOnStart(locale)),
                activeColor: appbarcolor,
                activeTrackColor: appbarcolor.withAlpha(140),
                inactiveThumbColor: cardcolor.withAlpha(200),
                inactiveTrackColor: cardcolor.withAlpha(90),
                onChanged: (v) => settings.setDefaultShuffle(v),
              ),
              _tileDivider(),
              _dropdownTile<String>(
                context,
                title: AppStrings.loopMode(locale),
                current: settings.defaultLoopMode,
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
                onChanged: (v) => settings.setDefaultLoopMode(v),
              ),
              _tileDivider(),
              _dropdownTile<double>(
                context,
                title: AppStrings.defaultVolume(locale),
                subtitle: 'New tracks will start at this volume',
                current: settings.defaultVolume,
                items: const [0.4, 0.6, 0.8, 1.0],
                itemLabel: (v) => '${(v * 100).round()}%',
                onChanged: (v) => settings.setDefaultVolume(v),
              ),
              _tileDivider(),
              _dropdownTile<String>(
                context,
                title: AppStrings.preferredAudioQuality(locale),
                subtitle: AppStrings.willApplyToNewTracks(locale),
                current: settings.preferredQuality,
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
                onChanged: (v) => settings.setPreferredQuality(v),
              ),
              _tileDivider(),
              ListTile(
                title: const Text('Equalizer'),
                subtitle: const Text('Adjust audio frequencies (Android only)'),
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
            _sectionCard([
              SwitchListTile(
                value: settings.duckOnInterruption,
                title: Text(AppStrings.duckOnInterruption(locale)),
                subtitle: Text(AppStrings.lowerVolumeOnInterruption(locale)),
                activeColor: appbarcolor,
                activeTrackColor: appbarcolor.withAlpha(140),
                inactiveThumbColor: cardcolor.withAlpha(200),
                inactiveTrackColor: cardcolor.withAlpha(90),
                onChanged: (v) => settings.setDuckOnInterruption(v),
              ),
              _tileDivider(),
              _dropdownTile<double>(
                context,
                title: AppStrings.duckVolume(locale),
                current: settings.duckVolume,
                items: const [0.2, 0.3, 0.4, 0.5, 0.6],
                itemLabel: (v) => '${(v * 100).round()}%',
                onChanged: (v) => settings.setDuckVolume(v),
              ),
              _tileDivider(),
              SwitchListTile(
                value: settings.autoResumeAfterInterruption,
                title: Text(AppStrings.autoResume(locale)),
                subtitle: const Text('Resume playback after short focus loss'),
                activeColor: appbarcolor,
                activeTrackColor: appbarcolor.withAlpha(140),
                inactiveThumbColor: cardcolor.withAlpha(200),
                inactiveTrackColor: cardcolor.withAlpha(90),
                onChanged: (v) => settings.setAutoResumeAfterInterruption(v),
              ),
            ]),

            _sectionHeader('General'),
            _sectionCard([
              _dropdownTile<String>(
                context,
                title: AppStrings.language(locale),
                current: settings.localeCode,
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
                onChanged: (v) => settings.setLocaleCode(v),
              ),
            ]),

            _sectionHeader('Search'),
            _sectionCard([
              SwitchListTile(
                value: settings.showRecentSearches,
                title: const Text('Show recent searches'),
                activeColor: appbarcolor,
                activeTrackColor: appbarcolor.withAlpha(140),
                inactiveThumbColor: cardcolor.withAlpha(200),
                inactiveTrackColor: cardcolor.withAlpha(90),
                onChanged: (v) => settings.setShowRecentSearches(v),
              ),
              _tileDivider(),
              SwitchListTile(
                value: settings.showSearchSuggestions,
                title: const Text('Show search suggestions'),
                activeColor: appbarcolor,
                activeTrackColor: appbarcolor.withAlpha(140),
                inactiveThumbColor: cardcolor.withAlpha(200),
                inactiveTrackColor: cardcolor.withAlpha(90),
                onChanged: (v) => settings.setShowSearchSuggestions(v),
              ),
            ]),

            _sectionHeader('Downloads'),
            _sectionCard([
              ListTile(
                title: const Text('Download Location'),
                subtitle: Text(settings.downloadPath),
                trailing: Icon(Icons.edit, color: appbarcolor),
                onTap: () => _showPathEditor(context, settings),
              ),
            ]),

            _sectionHeader(AppStrings.maintenance(locale)),
            _sectionCard([
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(AppStrings.clearStreamImageCache(locale)),
                subtitle: Text(AppStrings.fixesBadUrlsAndFreesMemory(locale)),
                onTap: () {
                  // Implement actual cache clearing service call later
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppStrings.cacheCleared(locale))),
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
                    await settings.resetToDefaults();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppStrings.settingsReset(locale))),
                    );
                  }
                },
              ),
            ]),

            _sectionHeader('Updates'),
            _sectionCard([
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('Check for update'),
                subtitle: const Text('Tap to query latest GitHub release'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Checking for updates...')),
                  );
                  final info = await UpdateService.instance.checkForUpdate();
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
            _sectionCard([
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
            _sectionCard([
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
                  // Copy email to clipboard
                  final data = const ClipboardData(
                    text: 'wambugukinyua125@gmail.com',
                  );
                  await Clipboard.setData(data);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Copied to clipboard')),
                  );
                },
              ),
            ]),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // Helpers
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

  Widget _sectionCard(List<Widget> children) {
    return Card(
      color: cardcolor,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      trailing: DropdownButton<T>(
        value: current,
        dropdownColor: cardcolor,
        style: TextStyle(color: txtcolor),
        iconEnabledColor: appbarcolor,
        underline: const SizedBox.shrink(),
        onChanged: (v) => v == null ? null : onChanged(v),
        items: items
            .map(
              (e) => DropdownMenuItem<T>(
                value: e,
                child: Text(itemLabel(e), style: TextStyle(color: txtcolor)),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showPathEditor(BuildContext context, SettingsService settings) {
    final controller = TextEditingController(text: settings.downloadPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardcolor,
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
              borderSide: BorderSide(color: appbarcolor),
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
              settings.setDownloadPath(controller.text);
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: appbarcolor)),
          ),
        ],
      ),
    );
  }
}
