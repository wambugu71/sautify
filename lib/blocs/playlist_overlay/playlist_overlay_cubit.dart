/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/playlist_extract.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'playlist_overlay_state.dart';

class PlaylistOverlayCubit extends Cubit<PlaylistOverlayState> {
  final PlaylistExtract _extract;

  PlaylistOverlayCubit({required String playlistId})
      : _extract = PlaylistExtract(playlistId: playlistId),
        super(const PlaylistOverlayState.loading());

  Future<void> init() async {
    await loadPlaylistVideos();
  }

  Future<void> loadPlaylistVideos() async {
    emit(state.copyWith(status: PlaylistOverlayStatus.loading, error: null));
    try {
      final videos = await _extract.fetchPlaylistVideos();
      if (videos.isEmpty) {
        emit(state.copyWith(
          status: PlaylistOverlayStatus.error,
          videos: const <Video>[],
          error: 'No videos found in this playlist',
        ));
        return;
      }

      emit(state.copyWith(
        status: PlaylistOverlayStatus.ready,
        videos: videos,
        error: null,
      ));

      await _warmFirstFew(videos);
    } catch (e) {
      emit(state.copyWith(
        status: PlaylistOverlayStatus.error,
        videos: const <Video>[],
        error: 'Failed to load playlist: ${e.toString()}',
      ));
    }
  }

  Future<void> _warmFirstFew(List<Video> videos) async {
    try {
      final items = videos.take(3).toList(growable: false);
      if (items.isEmpty) return;
      final ids = items.map((v) => v.id.value).toList(growable: false);
      final service = MusicStreamingService();
      await service.batchGetStreamingUrls(ids);
      service.dispose();
    } catch (_) {}
  }

  void beginStart(String videoId) {
    emit(state.copyWith(isBusy: true, startingTrackId: videoId));
  }

  void endStart() {
    emit(state.copyWith(isBusy: false, startingTrackId: null));
  }

  void setBusy(bool busy) {
    if (busy == state.isBusy) return;
    emit(state.copyWith(
        isBusy: busy, startingTrackId: busy ? state.startingTrackId : null));
  }
}

