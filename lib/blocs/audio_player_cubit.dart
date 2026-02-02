/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/audio_player_service.dart';

class AudioPlayerState extends Equatable {
  final StreamingData? currentTrack;
  final String? sourceType;
  final String? sourceName;
  final List<StreamingData> playlist;
  final int currentIndex;
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;
  final bool isPreparing;
  final LoopMode loopMode;
  final bool isShuffleEnabled;
  final int version;

  const AudioPlayerState({
    this.currentTrack,
    this.sourceType,
    this.sourceName,
    this.playlist = const [],
    this.currentIndex = 0,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isPreparing = false,
    this.loopMode = LoopMode.off,
    this.isShuffleEnabled = false,
    this.version = 0,
  });

  AudioPlayerState copyWith({
    StreamingData? currentTrack,
    String? sourceType,
    String? sourceName,
    List<StreamingData>? playlist,
    int? currentIndex,
    Duration? duration,
    Duration? position,
    Duration? bufferedPosition,
    bool? isPlaying,
    bool? isBuffering,
    bool? isPreparing,
    LoopMode? loopMode,
    bool? isShuffleEnabled,
    int? version,
  }) {
    return AudioPlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      sourceType: sourceType ?? this.sourceType,
      sourceName: sourceName ?? this.sourceName,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isPreparing: isPreparing ?? this.isPreparing,
      loopMode: loopMode ?? this.loopMode,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      version: version ?? this.version,
    );
  }

  @override
  List<Object?> get props => [
        currentTrack,
        sourceType,
        sourceName,
        playlist,
        currentIndex,
        duration,
        position,
        bufferedPosition,
        isPlaying,
        isBuffering,
        isPreparing,
        loopMode,
        isShuffleEnabled,
        version,
      ];
}

class AudioPlayerCubit extends Cubit<AudioPlayerState> {
  final AudioPlayerService service;
  StreamSubscription? _trackInfoSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _bufferedSub;
  StreamSubscription? _playerStateSub;
  VoidCallback? _preparingListener;

  AudioPlayerCubit(this.service) : super(const AudioPlayerState()) {
    // Seed initial snapshot from the already-running singleton service.
    // This prevents UI (e.g., MiniPlayer) from disappearing if this cubit is
    // recreated while audio is still playing.
    emit(
      state.copyWith(
        currentTrack: service.currentTrack,
        playlist: service.playlist,
        currentIndex: service.currentIndex,
        position: service.player.position,
        duration: service.player.duration ?? Duration.zero,
        bufferedPosition: service.player.bufferedPosition,
        isPlaying: service.player.playing,
        isBuffering:
            service.player.processingState == ProcessingState.buffering ||
                service.player.processingState == ProcessingState.loading,
      ),
    );

    _preparingListener = () {
      emit(state.copyWith(isPreparing: service.isPreparing.value));
    };
    service.isPreparing.addListener(_preparingListener!);
    emit(state.copyWith(isPreparing: service.isPreparing.value));

    _trackInfoSub = service.trackInfoStream.listen((info) {
      emit(state.copyWith(
        currentTrack: info.track,
        sourceType: info.sourceType,
        sourceName: info.sourceName,
        playlist: service.playlist,
        currentIndex: info.currentIndex,
        duration: info.duration ?? Duration.zero,
        isShuffleEnabled: info.isShuffleEnabled,
        loopMode: _parseLoopMode(info.loopMode),
        isPlaying: info.isPlaying,
        version: state.version + 1,
      ));
    });

    _positionSub = service.player.positionStream.listen((pos) {
      emit(state.copyWith(position: pos));
    });

    _bufferedSub = service.player.bufferedPositionStream.listen((buf) {
      emit(state.copyWith(bufferedPosition: buf));
    });

    _playerStateSub = service.player.playerStateStream.listen((playerState) {
      emit(state.copyWith(
        isPlaying: playerState.playing,
        isBuffering: playerState.processingState == ProcessingState.buffering ||
            playerState.processingState == ProcessingState.loading,
      ));
    });
  }

  LoopMode _parseLoopMode(String mode) {
    switch (mode) {
      case 'one':
        return LoopMode.one;
      case 'all':
        return LoopMode.all;
      default:
        return LoopMode.off;
    }
  }

  void playTrack(
    StreamingData track, {
    String? sourceType,
    String? sourceName,
    bool withTransition = true,
  }) {
    service.loadPlaylist(
      [track],
      sourceType: sourceType ?? 'QUEUE',
      sourceName: sourceName,
      withTransition: withTransition,
    );
  }

  void playPlaylist(
    List<StreamingData> playlist, {
    int index = 0,
    String? sourceType,
    String? sourceName,
    bool withTransition = true,
  }) {
    service.loadPlaylist(
      playlist,
      initialIndex: index,
      sourceType: sourceType ?? 'QUEUE',
      sourceName: sourceName,
      withTransition: withTransition,
    );
  }

  void togglePlayPause() {
    if (service.player.playing) {
      service.pause();
    } else {
      service.play();
    }
  }

  void next() => service.skipToNext();
  void previous() => service.skipToPrevious();

  Future<bool> seek(Duration position, {int? index}) =>
      service.seek(position, index: index);

  void toggleShuffle() {
    service.setShuffleModeEnabled(!state.isShuffleEnabled);
  }

  void setShuffle(bool enabled) {
    if (enabled == state.isShuffleEnabled) return;
    service.setShuffleModeEnabled(enabled);
  }

  void setLoopMode(LoopMode mode) {
    service.setLoopMode(mode);
  }

  void toggleRepeat() {
    final nextMode = state.loopMode == LoopMode.off
        ? LoopMode.all
        : (state.loopMode == LoopMode.all ? LoopMode.one : LoopMode.off);
    service.setLoopMode(nextMode);
  }

  @override
  Future<void> close() {
    final listener = _preparingListener;
    if (listener != null) {
      service.isPreparing.removeListener(listener);
    }
    _trackInfoSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _playerStateSub?.cancel();
    return super.close();
  }
}

