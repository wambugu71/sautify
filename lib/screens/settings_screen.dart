import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

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
                _sectionHeader('Playback'),
                _sectionCard([
                  SwitchListTile(
                    title: Text(
                      'Shuffle on start',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Enable shuffle by default',
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
                            'Loop mode',
                            style: TextStyle(color: txtcolor),
                          ),
                        ),
                        DropdownButton<String>(
                          value: settings.defaultLoopMode,
                          dropdownColor: cardcolor,
                          style: TextStyle(color: txtcolor),
                          items: const [
                            DropdownMenuItem(value: 'off', child: Text('Off')),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text('Repeat one'),
                            ),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Repeat all'),
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
                      'Playback speed',
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
                      'Default volume',
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
                            'Preferred audio quality',
                            style: TextStyle(color: txtcolor),
                          ),
                        ),
                        DropdownButton<String>(
                          value: settings.preferredQuality,
                          dropdownColor: cardcolor,
                          style: TextStyle(color: txtcolor),
                          items: const [
                            DropdownMenuItem(
                              value: 'low',
                              child: Text('Low (64-128 kbps)'),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('Medium (128-192 kbps)'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('High (256-320 kbps)'),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await settings.setPreferredQuality(v);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Quality will apply to new tracks',
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
                      'Crossfade (coming soon)',
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

                _sectionHeader('Audio Focus & Interruptions'),
                _sectionCard([
                  SwitchListTile(
                    title: Text(
                      'Duck on interruption',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Lower volume on transient interruptions',
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
                      'Duck volume',
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
                      'Auto-resume after interruption',
                      style: TextStyle(color: txtcolor),
                    ),
                    value: settings.autoResumeAfterInterruption,
                    onChanged: (v) async {
                      await settings.setAutoResumeAfterInterruption(v);
                    },
                  ),
                ]),

                _sectionHeader('Maintenance'),
                _sectionCard([
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services_outlined,
                      color: appbarcolor,
                    ),
                    title: Text(
                      'Clear stream/image cache',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Fixes bad URLs and frees memory',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    trailing: _primaryChip('Clear'),
                    onTap: () {
                      AudioPlayerService().clearCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleared')),
                      );
                    },
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.refresh_outlined, color: appbarcolor),
                    title: Text(
                      'Reset all settings',
                      style: TextStyle(color: txtcolor),
                    ),
                    trailing: _primaryChip('Reset'),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: cardcolor,
                          title: Text(
                            'Reset settings?',
                            style: TextStyle(color: txtcolor),
                          ),
                          content: Text(
                            'This will restore default playback and audio focus settings.',
                            style: TextStyle(color: txtcolor.withAlpha(180)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appbarcolor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Reset'),
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
                          const SnackBar(content: Text('Settings reset')),
                        );
                      }
                    },
                  ),
                ]),

                _sectionHeader('About'),
                _sectionCard([
                  ListTile(
                    leading: Icon(Icons.info_outline, color: appbarcolor),
                    title: Text('App info', style: TextStyle(color: txtcolor)),
                    subtitle: Text(
                      'Sautify v1.0.0',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Sautify',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Icon(Icons.library_music),
                        children: const [
                          Text(
                            'A modern music streaming player built with Flutter.',
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
                      'Privacy & permissions',
                      style: TextStyle(color: txtcolor),
                    ),
                    subtitle: Text(
                      'Notifications, storage, network',
                      style: TextStyle(color: txtcolor.withAlpha(160)),
                    ),
                    onTap: () {},
                  ),
                  _tileDivider(),
                  ListTile(
                    leading: Icon(Icons.article_outlined, color: appbarcolor),
                    title: Text(
                      'Open source licenses',
                      style: TextStyle(color: txtcolor),
                    ),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'Sautify',
                        applicationVersion: '1.0.0',
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
