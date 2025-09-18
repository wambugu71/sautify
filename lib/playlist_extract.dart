/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistExtract {
  final String playlistId;
  YoutubeExplode? _yt;

  PlaylistExtract({required this.playlistId});

  Future<List<Video>> fetchPlaylistVideos() async {
    _yt = YoutubeExplode();
    try {
      var videos = await _yt!.playlists.getVideos(playlistId).toList();
      return videos;
    } catch (e) {
      print('Error fetching playlist videos: $e');
      return [];
    } finally {
      _yt?.close();
    }
  }
}
