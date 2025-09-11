import 'package:flutter/material.dart';
import 'package:sautifyv2/playlist_extract.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistProvider extends ChangeNotifier {
  final String playlistId;
  final PlaylistExtract _playlistExtract;
  
  List<Video> _videos = [];
  bool _isLoading = false;
  String? _error;

  PlaylistProvider(this.playlistId) : _playlistExtract = PlaylistExtract(playlistId: playlistId) {
    loadPlaylistVideos();
  }

  List<Video> get videos => _videos;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPlaylistVideos() async {
    if (playlistId.isEmpty) {
      _error = 'Invalid playlist ID';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _videos = await _playlistExtract.fetchPlaylistVideos();
      
      if (_videos.isEmpty) {
        _error = 'No videos found in this playlist';
      }
    } catch (e) {
      _error = 'Failed to load playlist: ${e.toString()}';
      _videos = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }
}
