/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_oknob/flutter_oldschool_knob.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautifyv2/features/equalizer/data/equalizer_repository_impl.dart';
import 'package:sautifyv2/features/equalizer/presentation/cubit/equalizer_cubit.dart';
import 'package:sautifyv2/features/equalizer/presentation/cubit/equalizer_state.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => EqualizerCubit(
        repo: EqualizerRepositoryImpl(
          audio: AudioPlayerService(),
          settings: SettingsService(),
        ),
      )..init(),
      child: const _EqualizerView(),
    );
  }
}

class _EqualizerView extends StatelessWidget {
  const _EqualizerView();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final scaffoldBackgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    if (!Platform.isAndroid) {
      return Scaffold(
        backgroundColor: scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Equalizer'),
          backgroundColor: scaffoldBackgroundColor,
          foregroundColor: textColor,
        ),
        body: Center(
          child: Text(
            'Equalizer is only available on Android',
            style: TextStyle(color: textColor),
          ),
        ),
      );
    }

    return BlocBuilder<EqualizerCubit, EqualizerState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Equalizer'),
            backgroundColor: scaffoldBackgroundColor,
            foregroundColor: textColor,
            actions: [
              Switch(
                value: state.enabled,
                onChanged: state.status == EqualizerStatus.ready
                    ? (value) =>
                        context.read<EqualizerCubit>().setEnabled(value)
                    : null,
                activeThumbColor: primaryColor,
              ),
            ],
          ),
          body: switch (state.status) {
            EqualizerStatus.loading => Center(
                child: LoadingIndicatorM3E(
                  containerColor: primaryColor.withAlpha(100),
                  variant: LoadingIndicatorM3EVariant.contained,
                  color: primaryColor,
                ),
              ),
            EqualizerStatus.unavailable => Center(
                child: Text(
                  state.isSupported
                      ? 'Equalizer not available'
                      : 'Equalizer is only available on Android',
                  style: TextStyle(color: textColor),
                ),
              ),
            EqualizerStatus.ready => _BandsView(state: state),
          },
        );
      },
    );
  }
}

class _BandsView extends StatelessWidget {
  final EqualizerState state;
  const _BandsView({required this.state});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final cardColor = Theme.of(context).cardColor;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: state.bands.map((band) {
                final freq = band.centerFrequencyHz;
                final freqLabel = freq < 1000
                    ? '$freq Hz'
                    : '${(freq / 1000).toStringAsFixed(1)} kHz';

                final currentGain = band.gainDb;

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
                            value: currentGain.clamp(-15.0, 15.0),
                            min: -15.0,
                            max: 15.0,
                            activeColor:
                                state.enabled ? primaryColor : Colors.grey,
                            inactiveColor: cardColor,
                            onChanged: state.enabled
                                ? (value) => context
                                    .read<EqualizerCubit>()
                                    .setBandGain(band.index, value)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      freqLabel,
                      style: TextStyle(
                        color: state.enabled ? textColor : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currentGain.toStringAsFixed(1)} dB',
                      style: TextStyle(
                        color: state.enabled
                            ? textColor.withAlpha(150)
                            : Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: state.enabled
                ? () => context.read<EqualizerCubit>().resetBands()
                : null,
            child: Text(
              'Reset to Flat',
              style: TextStyle(
                color: state.enabled ? primaryColor : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _SpeedAndPitchControl(state: state),
          const SizedBox(height: 10),
          _SkipSilenceControl(state: state),
          const SizedBox(height: 10),
          _LoudnessEnhancerControl(state: state),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SkipSilenceControl extends StatelessWidget {
  final EqualizerState state;
  const _SkipSilenceControl({required this.state});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Skip Silence', style: TextStyle(color: textColor)),
          Switch(
            value: state.skipSilenceEnabled,
            onChanged: (value) =>
                context.read<EqualizerCubit>().setSkipSilenceEnabled(value),
            activeThumbColor: primaryColor,
          ),
        ],
      ),
    );
  }
}

class _LoudnessEnhancerControl extends StatelessWidget {
  final EqualizerState state;
  const _LoudnessEnhancerControl({required this.state});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Loudness Enhancer', style: TextStyle(color: textColor)),
              Switch(
                value: state.loudnessEnhancerEnabled,
                onChanged: (value) => context
                    .read<EqualizerCubit>()
                    .setLoudnessEnhancerEnabled(value),
                activeThumbColor: primaryColor,
              ),
            ],
          ),
        ),
        if (state.loudnessEnhancerEnabled)
          Column(
            children: [
              const SizedBox(height: 10),
              SizedBox(
                width: 140,
                height: 170,
                child: FlutterOKnob(
                  minValue: -10.0,
                  maxValue: 20.0,
                  size: 140,
                  knobvalue: state.loudnessEnhancerTargetGain,
                  showKnobLabels: false,
                  maxRotationAngle: 180,
                  sensitivity: 0.6,
                  onChanged: (value) {
                    final clamped = value.clamp(0.0, 20.0);
                    final rounded = double.parse(clamped.toStringAsFixed(1));
                    context
                        .read<EqualizerCubit>()
                        .setLoudnessEnhancerTargetGain(rounded);
                  },
                  knobLabel: Text(
                    'Gain',
                    style: TextStyle(color: textColor),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gain: ${state.loudnessEnhancerTargetGain.toStringAsFixed(1)} dB',
                style: TextStyle(color: textColor),
              ),
            ],
          ),
      ],
    );
  }
}

class _SpeedAndPitchControl extends StatelessWidget {
  final EqualizerState state;
  const _SpeedAndPitchControl({required this.state});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              SizedBox(
                width: 140,
                height: 170,
                child: FlutterOKnob(
                  minValue: 0.5,
                  maxValue: 2.0,
                  size: 140,
                  markerColor: primaryColor,
                  knobvalue: state.playbackSpeed,
                  showKnobLabels: false,
                  maxRotationAngle: 180,
                  sensitivity: 0.6,
                  onChanged: (value) {
                    final clamped = value.clamp(0.5, 2.0);
                    final rounded = double.parse(clamped.toStringAsFixed(2));
                    context.read<EqualizerCubit>().setPlaybackSpeed(rounded);
                  },
                  knobLabel: Text('Speed', style: TextStyle(color: textColor)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Speed: ${state.playbackSpeed.toStringAsFixed(2)}x',
                style: TextStyle(color: textColor),
              ),
            ],
          ),
          Column(
            children: [
              SizedBox(
                width: 140,
                height: 170,
                child: FlutterOKnob(
                  minValue: 0.5,
                  maxValue: 2.0,
                  markerColor: primaryColor,
                  size: 140,
                  knobvalue: state.pitch,
                  showKnobLabels: false,
                  maxRotationAngle: 180,
                  sensitivity: 0.6,
                  onChanged: (value) {
                    final clamped = value.clamp(0.5, 2.0);
                    final rounded = double.parse(clamped.toStringAsFixed(2));
                    context.read<EqualizerCubit>().setPitch(rounded);
                  },
                  knobLabel: Text('Pitch', style: TextStyle(color: textColor)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pitch: ${state.pitch.toStringAsFixed(2)}x',
                style: TextStyle(color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

