/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class PlayerState extends Equatable {
  final List<Color> bgColors;
  final bool showLyrics;
  final bool lyricsLoading;
  final String? lyricsError;
  final List<LyricLine> lyrics;
  final int activeLyricIndex;
  final String? lyricsSource;

  const PlayerState({
    this.bgColors = const [Colors.black, Colors.black, Colors.black],
    this.showLyrics = false,
    this.lyricsLoading = false,
    this.lyricsError,
    this.lyrics = const [],
    this.activeLyricIndex = -1,
    this.lyricsSource,
  });

  PlayerState copyWith({
    List<Color>? bgColors,
    bool? showLyrics,
    bool? lyricsLoading,
    String? lyricsError,
    List<LyricLine>? lyrics,
    int? activeLyricIndex,
    String? lyricsSource,
  }) {
    return PlayerState(
      bgColors: bgColors ?? this.bgColors,
      showLyrics: showLyrics ?? this.showLyrics,
      lyricsLoading: lyricsLoading ?? this.lyricsLoading,
      lyricsError: lyricsError,
      lyrics: lyrics ?? this.lyrics,
      activeLyricIndex: activeLyricIndex ?? this.activeLyricIndex,
      lyricsSource: lyricsSource ?? this.lyricsSource,
    );
  }

  @override
  List<Object?> get props => [
        bgColors,
        showLyrics,
        lyricsLoading,
        lyricsError,
        lyrics,
        activeLyricIndex,
        lyricsSource,
      ];
}

class LyricLine {
  final String text;
  final int startTimeMs;
  final int endTimeMs;

  LyricLine(this.text, this.startTimeMs, this.endTimeMs);
}

