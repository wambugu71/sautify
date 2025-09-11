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
