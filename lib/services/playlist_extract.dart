/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistExtract {
  final String playlistId;
  final YoutubeExplode yt;

  PlaylistExtract({required this.playlistId}) : yt = YoutubeExplode();
  Future<List<Video>> fetchPlaylistVideos() async {
    try {
      var videos = await yt.playlists.getVideos(playlistId).toList();
      return videos;
    } catch (e) {
      return [];
      //  throw Exception('Error fetching playlist videos: $e');
      //   print('Error fetching playlist videos: $e');
    } finally {
      yt.close();
    }
  }
}
