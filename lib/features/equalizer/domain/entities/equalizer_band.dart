/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';

class EqualizerBand extends Equatable {
  final int index;
  final int centerFrequencyHz;
  final double gainDb;

  const EqualizerBand({
    required this.index,
    required this.centerFrequencyHz,
    required this.gainDb,
  });

  EqualizerBand copyWith({double? gainDb}) {
    return EqualizerBand(
      index: index,
      centerFrequencyHz: centerFrequencyHz,
      gainDb: gainDb ?? this.gainDb,
    );
  }

  @override
  List<Object?> get props => [index, centerFrequencyHz, gainDb];
}

