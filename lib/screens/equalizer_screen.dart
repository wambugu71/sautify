import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final _audioService = AudioPlayerService();
  final _settings = SettingsService();
  AndroidEqualizerParameters? _parameters;
  bool _isLoading = true;
  bool _isEnabled = false;

  @override
  void initState() {
    super.initState();
    _initEqualizer();
  }

  Future<void> _initEqualizer() async {
    if (!Platform.isAndroid) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      _parameters = await _audioService.equalizer.parameters;
      _isEnabled = _settings.equalizerEnabled;
      // Ensure equalizer state matches settings
      await _audioService.equalizer.setEnabled(_isEnabled);
    } catch (e) {
      debugPrint('Error initializing equalizer: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Scaffold(
        backgroundColor: bgcolor,
        appBar: AppBar(
          title: const Text('Equalizer'),
          backgroundColor: bgcolor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'Equalizer is only available on Android',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgcolor,
      appBar: AppBar(
        title: const Text('Equalizer'),
        backgroundColor: bgcolor,
        foregroundColor: Colors.white,
        actions: [
          Switch(
            value: _isEnabled,
            onChanged: (value) async {
              setState(() => _isEnabled = value);
              await _settings.setEqualizerEnabled(value);
              await _audioService.equalizer.setEnabled(value);
            },
            activeColor: appbarcolor,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: LoadingIndicatorM3E(
                containerColor: appbarcolor.withAlpha(100),
                variant: LoadingIndicatorM3EVariant.contained,
                color: appbarcolor,
              ),
            )
          : _parameters == null
          ? const Center(
              child: Text(
                'Equalizer not available',
                style: TextStyle(color: Colors.white),
              ),
            )
          : _buildBands(),
    );
  }

  Widget _buildBands() {
    final bands = _parameters!.bands;
    final minDecibels = _parameters!.minDecibels;
    final maxDecibels = _parameters!.maxDecibels;

    return Column(
      children: [
        const SizedBox(height: 20),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: bands.map((band) {
              final freq = band.centerFrequency;
              final freqLabel = freq < 1000
                  ? '${freq.toInt()} Hz'
                  : '${(freq / 1000).toStringAsFixed(1)} kHz';

              // Get current gain from settings or default to 0
              final currentGain = _settings.equalizerBands[band.index] ?? 0.0;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                        ),
                        child: Slider(
                          value: currentGain.clamp(minDecibels, maxDecibels),
                          min: minDecibels,
                          max: maxDecibels,
                          activeColor: _isEnabled ? appbarcolor : Colors.grey,
                          inactiveColor: cardcolor,
                          onChanged: _isEnabled
                              ? (value) async {
                                  setState(() {
                                    _settings.equalizerBands[band.index] =
                                        value;
                                  });
                                  await band.setGain(value);
                                  _settings.setEqualizerBand(band.index, value);
                                }
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    freqLabel,
                    style: TextStyle(
                      color: _isEnabled ? txtcolor : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currentGain.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      color: _isEnabled ? txtcolor.withAlpha(150) : Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        // Reset button
        TextButton(
          onPressed: _isEnabled
              ? () async {
                  for (final band in bands) {
                    await band.setGain(0.0);
                    await _settings.setEqualizerBand(band.index, 0.0);
                  }
                  setState(() {});
                }
              : null,
          child: Text(
            'Reset to Flat',
            style: TextStyle(color: _isEnabled ? appbarcolor : Colors.grey),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
