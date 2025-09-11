import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();
  final MusicStreamingService _streamingService = MusicStreamingService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  ConcatenatingAudioSource? _audioSource;

  List<StreamingData> _playlist = [];
  int _currentIndex = 0;
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  String? _lastRecentVideoId;

  // New: source context
  String? _sourceName; // e.g., playlist/album name
  String _sourceType = 'QUEUE'; // PLAYLIST, ALBUM, SEARCH, LIBRARY, QUEUE

  // Track state across audio interruptions
  bool _resumeAfterInterruption = false;
  double _preDuckVolume = 1.0;

  // Preloading control
  static const int _preloadCount = 5; // how many upcoming items to preload
  final Set<int> _preloadedIndices = <int>{};

  // Current track stream controller
  final StreamController<StreamingData?> _currentTrackController =
      StreamController<StreamingData?>.broadcast();

  // Event-driven TrackInfo broadcaster (replaces periodic polling)
  final StreamController<TrackInfo> _trackInfoController =
      StreamController<TrackInfo>.broadcast();
  TrackInfo? _lastTrackInfo;
  DateTime _lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // Expose preparation/loading state for UI skeletons
  final ValueNotifier<bool> isPreparing = ValueNotifier<bool>(false);

  // Concurrency guards
  int _loadRequestId = 0; // monotonically increasing id for load operations
  bool _seekInProgress = false;
  int? _pendingSeekIndex;
  Duration _pendingSeekPosition = Duration.zero;

  // Getters
  AudioPlayer get player => _player;
  List<StreamingData> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isShuffleEnabled => _isShuffleEnabled;
  LoopMode get loopMode => _loopMode;
  StreamingData? get currentTrack =>
      _playlist.isNotEmpty && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;

  // Stream getters
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  Stream<bool> get shuffleModeEnabledStream => _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<StreamingData?> get currentTrackStream {
    return Stream.multi((controller) {
      // Immediately emit current track
      controller.add(currentTrack);

      // Listen to future updates
      final subscription = _currentTrackController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );

      controller.onCancel = () => subscription.cancel();
    });
  }

  /// Optimized, event-driven TrackInfo stream
  Stream<TrackInfo> get trackInfoStream => _trackInfoController.stream;

  // Allow screens to set source context
  void setSourceContext({String? name, String type = 'QUEUE'}) {
    _sourceName = name;
    _sourceType = type;
    _emitTrackInfo(force: true);
  }

  // Build the latest TrackInfo snapshot from player state
  TrackInfo _computeTrackInfo() {
    final track = currentTrack;
    final playerState = _player.playerState;
    final position = _player.position;
    final duration = _player.duration;
    final shuffleEnabled = _player.shuffleModeEnabled;
    final loopMode = _player.loopMode;

    final progress = duration != null && duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    String loopModeString = 'off';
    switch (loopMode) {
      case LoopMode.off:
        loopModeString = 'off';
        break;
      case LoopMode.one:
        loopModeString = 'one';
        break;
      case LoopMode.all:
        loopModeString = 'all';
        break;
    }

    return TrackInfo(
      track: track,
      currentIndex: _currentIndex,
      totalTracks: _playlist.length,
      isPlaying: playerState.playing,
      isShuffleEnabled: shuffleEnabled,
      loopMode: loopModeString,
      position: position,
      duration: duration,
      progress: progress.clamp(0.0, 1.0),
      sourceName: _sourceName,
      sourceType: _sourceType,
    );
  }

  // Emit TrackInfo with simple throttling for position changes
  void _emitTrackInfo({bool force = false}) {
    final now = DateTime.now();
    final info = _computeTrackInfo();

    bool otherChanged = false;
    if (_lastTrackInfo == null) {
      otherChanged = true;
    } else {
      final prev = _lastTrackInfo!;
      otherChanged =
          (info.track?.videoId != prev.track?.videoId) ||
          info.currentIndex != prev.currentIndex ||
          info.totalTracks != prev.totalTracks ||
          info.isPlaying != prev.isPlaying ||
          info.isShuffleEnabled != prev.isShuffleEnabled ||
          info.loopMode != prev.loopMode ||
          (info.duration?.inMilliseconds ?? -1) !=
              (prev.duration?.inMilliseconds ?? -1) ||
          info.sourceName != prev.sourceName ||
          info.sourceType != prev.sourceType;
    }

    final lastPosMs = _lastTrackInfo?.position.inMilliseconds ?? -1;
    final posDeltaMs = (info.position.inMilliseconds - lastPosMs).abs();
    final canEmitProgress =
        now.difference(_lastProgressEmit) > const Duration(milliseconds: 250);
    final significantProgress = posDeltaMs >= 200;

    if (force || otherChanged || (significantProgress && canEmitProgress)) {
      _trackInfoController.add(info);
      _lastTrackInfo = info;
      _lastProgressEmit = now;
    }
  }

  /// Initialize the audio service
  Future<void> initialize() async {
    // Load settings
    final settings = SettingsService();
    if (!settings.isReady) {
      await settings.init();
    }

    // Configure audio session for proper focus/ducking and interruptions
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());

    // Crossfade not supported with current just_audio version; value persisted for future use

    // Apply default speed, shuffle, loop
    try {
      await _player.setSpeed(settings.defaultPlaybackSpeed);
    } catch (_) {}

    // Apply default volume
    try {
      await _player.setVolume(settings.defaultVolume);
    } catch (_) {}

    await setShuffleModeEnabled(settings.defaultShuffle);
    switch (settings.defaultLoopMode) {
      case 'one':
        await setLoopMode(LoopMode.one);
        break;
      case 'all':
        await setLoopMode(LoopMode.all);
        break;
      default:
        await setLoopMode(LoopMode.off);
    }

    // Handle becoming noisy (e.g., headphones unplugged)
    session.becomingNoisyEventStream.listen((_) {
      pause();
    });

    // Handle interruptions (phone calls, navigation, etc.) respecting settings
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (settings.duckOnInterruption) {
              _preDuckVolume = _player.volume;
              _player.setVolume(settings.duckVolume);
            } else {
              _resumeAfterInterruption = _player.playing;
              pause();
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _resumeAfterInterruption = _player.playing;
            pause();
            break;
        }
      } else {
        // End of interruption
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (settings.duckOnInterruption) {
              _player.setVolume(_preDuckVolume);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_resumeAfterInterruption &&
                settings.autoResumeAfterInterruption) {
              play();
            }
            _resumeAfterInterruption = false;
            break;
        }
      }
    });

    // Android-specific audio attributes for media playback
    await _player.setAndroidAudioAttributes(
      const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
        flags: AndroidAudioFlags.none,
      ),
    );

    // Emit initial current track
    _currentTrackController.add(currentTrack);
    _emitTrackInfo(force: true);

    // Listen to player events
    _player.currentIndexStream.listen((audioIndex) {
      if (audioIndex != null) {
        // Convert audio source index back to playlist index
        final newIndex = _getPlaylistIndexFromAudioIndex(audioIndex);
        if (newIndex != _currentIndex) {
          _currentIndex = newIndex;
          _currentTrackController.add(currentTrack);
          _emitTrackInfo(force: true);
          notifyListeners();
          _preloadUpcomingSongs();
        }
      }
    });

    _player.loopModeStream.listen((mode) {
      _loopMode = mode;
      _emitTrackInfo(force: true);
      notifyListeners();
    });

    _player.shuffleModeEnabledStream.listen((enabled) {
      _isShuffleEnabled = enabled;
      _emitTrackInfo(force: true);
      notifyListeners();
    });

    // Position/duration/state updates (progress bar & play/pause)
    _player.positionStream.listen((_) => _emitTrackInfo());
    _player.durationStream.listen((_) => _emitTrackInfo(force: true));

    // Handle playback completion and recents logging
    _player.playerStateStream.listen((state) {
      _emitTrackInfo(force: true);
      if (state.processingState == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }

      // When playback starts (playing & ready), log to recents
      if (state.playing && state.processingState == ProcessingState.ready) {
        final t = currentTrack;
        if (t != null && t.videoId != _lastRecentVideoId) {
          LibraryStore.addRecent(t);
          _lastRecentVideoId = t.videoId;
        }
      }
    });
  }

  /// Load and play a playlist with gapless playback
  Future<void> loadPlaylist(
    List<StreamingData> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    String? sourceName,
    String sourceType = 'QUEUE',
  }) async {
    // Bump request id to cancel any in-flight load operations
    final int requestId = ++_loadRequestId;
    isPreparing.value = true;
    try {
      _playlist = tracks;
      _currentIndex = initialIndex;
      _preloadedIndices.clear();

      // Set source context
      _sourceName = sourceName;
      _sourceType = sourceType;

      // Ensure the selected track is ready first for correct index mapping
      await _ensureTrackReady(_currentIndex, requestId: requestId);
      if (requestId != _loadRequestId) return; // superseded by newer request

      // Build audio source in order of playlist using only ready tracks
      await _rebuildAudioSource(
        preferPlaylistIndex: _currentIndex,
        preservePosition: false,
        requestId: requestId,
      );
      if (requestId != _loadRequestId) return;

      await _player.setShuffleModeEnabled(_isShuffleEnabled);
      await _player.setLoopMode(_loopMode);

      if (autoPlay) {
        // Seek to the selected index and start playback
        await seek(Duration.zero, index: _currentIndex);
      }

      // Preload upcoming tracks
      _preloadUpcomingSongs();

      // Preload album art images for current and upcoming tracks
      _preloadImages();

      // Emit initial current track
      _currentTrackController.add(currentTrack);
      _emitTrackInfo(force: true);
      notifyListeners();
    } catch (e) {
      print('Error loading playlist: $e');
      rethrow;
    } finally {
      // Only the latest request clears the preparing flag
      if (requestId == _loadRequestId) {
        isPreparing.value = false;
      }
    }
  }

  /// Add a single track to the current playlist
  Future<void> addTrack(StreamingData track) async {
    _playlist.add(track);

    // Rebuild audio source to keep order consistent when a track becomes ready
    if (track.isReady) {
      await _rebuildAudioSource();
    }

    notifyListeners();
  }

  /// Insert track at specific position
  Future<void> insertTrack(int index, StreamingData track) async {
    _playlist.insert(index, track);

    // Rebuild audio source to keep order consistent when a track becomes ready
    if (track.isReady) {
      await _rebuildAudioSource(preferPlaylistIndex: _currentIndex);
    }

    notifyListeners();
  }

  /// Remove track at index
  Future<void> removeTrack(int index) async {
    if (index < _playlist.length) {
      _playlist.removeAt(index);

      // Rebuild to keep indices in sync
      await _rebuildAudioSource(
        preferPlaylistIndex: _currentIndex > 0 ? _currentIndex - 1 : 0,
      );

      if (_currentIndex > index) {
        _currentIndex--;
      }

      notifyListeners();
    }
  }

  /// Move track from one position to another
  Future<void> moveTrack(int from, int to) async {
    if (from < _playlist.length && to < _playlist.length) {
      final track = _playlist.removeAt(from);
      _playlist.insert(to, track);

      // Rebuild to maintain correct order in player source
      await _rebuildAudioSource(preferPlaylistIndex: _currentIndex);
      notifyListeners();
    }
  }

  /// Play current track
  Future<void> play() async {
    await _ensureCurrentTrackReady();
    await _player.play();
  }

  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position, {int? index}) async {
    // Queue rapid track-change seeks to avoid races
    if (index != null) {
      if (_seekInProgress) {
        _pendingSeekIndex = index;
        _pendingSeekPosition = position;
        return;
      }
      _seekInProgress = true;
      try {
        await _seekInternal(position, index: index);
      } finally {
        _seekInProgress = false;
        // Process the latest pending seek if any
        if (_pendingSeekIndex != null) {
          final nextIndex = _pendingSeekIndex!;
          final nextPos = _pendingSeekPosition;
          _pendingSeekIndex = null;
          await seek(nextPos, index: nextIndex);
        }
      }
      return;
    }

    // Position-only seek
    await _player.seek(position);
  }

  Future<void> _seekInternal(Duration position, {required int index}) async {
    if (index >= 0 && index < _playlist.length) {
      isPreparing.value = true;
      try {
        // Ensure the target track is ready
        await _ensureTrackReady(index);

        // Check if the track is actually ready now
        if (!_playlist[index].isReady) {
          print('Warning: Track at index $index is not ready for playback');
          return;
        }

        // Update current index when seeking to a specific track
        if (index != _currentIndex) {
          _currentIndex = index;
          _currentTrackController.add(currentTrack);
          _emitTrackInfo(force: true);
          notifyListeners();

          // Preload images for the new current track and upcoming tracks
          _preloadImages();
        }

        // Convert playlist index to audio source index
        final audioSourceIndex = _getAudioSourceIndex(index);

        // Ensure the audio source index is valid
        if (audioSourceIndex >= 0 && _audioSource != null) {
          try {
            await _player.seek(position, index: audioSourceIndex);
            await _player.play(); // Ensure playback starts
          } catch (e) {
            print('Error seeking to audio source index $audioSourceIndex: $e');
            // Fallback: try to play without seeking to specific index
            await _player.play();
          }
        }
      } finally {
        isPreparing.value = false;
      }
    }
  }

  /// Skip to next track
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;

    int nextIndex = (_currentIndex + 1) % _playlist.length;

    // Use the seek method which handles all the complexity
    await seek(Duration.zero, index: nextIndex);
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;
    int prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;

    // Use the seek method which handles all the complexity
    await seek(Duration.zero, index: prevIndex);
  }

  /// Get the playlist index from an audio source index
  int _getPlaylistIndexFromAudioIndex(int audioIndex) {
    if (audioIndex < 0) return _currentIndex;

    int currentAudioIndex = 0;
    for (int i = 0; i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
        if (currentAudioIndex == audioIndex) {
          return i;
        }
        currentAudioIndex++;
      }
    }
    return _currentIndex; // Fallback to current index
  }

  /// Get the index in the audio source for a playlist index
  int _getAudioSourceIndex(int playlistIndex) {
    if (playlistIndex < 0 || playlistIndex >= _playlist.length) {
      return 0; // Fallback to first track
    }

    int audioIndex = 0;
    for (int i = 0; i < playlistIndex && i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
        audioIndex++;
      }
    }

    // Ensure the target track itself is ready
    if (!_playlist[playlistIndex].isReady ||
        _playlist[playlistIndex].streamUrl == null) {
      // Find the nearest ready track
      for (int i = playlistIndex; i < _playlist.length; i++) {
        if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
          return _getAudioSourceIndex(i);
        }
      }
      // If no track after, try before
      for (int i = playlistIndex - 1; i >= 0; i--) {
        if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
          return _getAudioSourceIndex(i);
        }
      }
      return 0; // Fallback
    }

    return audioIndex;
  }

  /// Set shuffle mode
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _isShuffleEnabled = enabled;
    await _player.setShuffleModeEnabled(enabled);
    notifyListeners();
  }

  /// Set loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _player.setLoopMode(mode);
    notifyListeners();
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Set volume
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  StreamingQuality _getPreferredQuality() {
    final pref = SettingsService().preferredQuality;
    switch (pref) {
      case 'low':
        return StreamingQuality.low;
      case 'high':
        return StreamingQuality.high;
      case 'medium':
      default:
        return StreamingQuality.medium;
    }
  }

  /// Batch process multiple tracks to get streaming URLs
  Future<void> _batchProcessTracks(List<String> videoIds) async {
    final result = await _streamingService.batchGetStreamingUrls(
      videoIds,
      quality: _getPreferredQuality(),
    );

    if (kDebugMode) {
      print(
        'Batch processing completed: ${result.successCount}/${result.totalCount} '
        'in ${result.processingTime.inMilliseconds}ms',
      );
    }

    // Update playlist with processed results
    bool anyUpdated = false;
    for (final streamingData in result.successful) {
      final index = _playlist.indexWhere(
        (track) => track.videoId == streamingData.videoId,
      );
      if (index != -1) {
        final wasReady = _playlist[index].isReady;
        final old = _playlist[index];

        // Prefer provider thumbnail (often higher quality) when available
        final merged = old.copyWith(
          title: old.title.isNotEmpty ? old.title : streamingData.title,
          artist: old.artist.isNotEmpty ? old.artist : streamingData.artist,
          thumbnailUrl:
              streamingData.thumbnailUrl ?? old.thumbnailUrl, // prefer new
          duration: old.duration ?? streamingData.duration,
          // Always take fresh streaming details
          streamUrl: streamingData.streamUrl,
          quality: streamingData.quality,
          cachedAt: streamingData.cachedAt,
          isAvailable: streamingData.isAvailable,
        );

        _playlist[index] = merged;
        if (!wasReady && merged.isReady) {
          anyUpdated = true;
        }
      }
    }

    // Rebuild audio source once to preserve order and indices
    if (anyUpdated) {
      await _rebuildAudioSource();
    }
  }

  /// Ensure current track is ready for playback
  Future<void> _ensureCurrentTrackReady() async {
    await _ensureTrackReady(_currentIndex);
  }

  /// Ensure specific track is ready for playback
  Future<void> _ensureTrackReady(int index, {int? requestId}) async {
    if (index >= _playlist.length) return;

    final track = _playlist[index];
    if (!track.isReady) {
      final result = await _streamingService.fetchStreamingData(
        track.videoId,
        _getPreferredQuality(),
      );

      if (result != null && result.isReady) {
        final old = _playlist[index];
        final merged = old.copyWith(
          title: old.title.isNotEmpty ? old.title : result.title,
          artist: old.artist.isNotEmpty ? old.artist : result.artist,
          thumbnailUrl: result.thumbnailUrl ?? old.thumbnailUrl, // prefer new
          duration: old.duration ?? result.duration,
          streamUrl: result.streamUrl,
          quality: result.quality,
          cachedAt: result.cachedAt,
          isAvailable: result.isAvailable,
        );

        _playlist[index] = merged;

        // Rebuild the audio source to include this track in the right position
        await _rebuildAudioSource(
          preferPlaylistIndex: index,
          preservePosition: false,
          requestId: requestId,
        );
      }
    }
  }

  /// Preload upcoming songs for smooth playback
  Future<void> _preloadUpcomingSongs() async {
    final upcomingIndices = _getUpcomingIndices();
    final newIndicesToPreload = upcomingIndices
        .where((index) => !_preloadedIndices.contains(index))
        .toList();

    if (newIndicesToPreload.isNotEmpty) {
      final videoIds = newIndicesToPreload
          .map((index) => _playlist[index].videoId)
          .toList();

      await _batchProcessTracks(videoIds);
      _preloadedIndices.addAll(newIndicesToPreload);
    }
  }

  /// Get indices of upcoming tracks to preload
  List<int> _getUpcomingIndices() {
    final indices = <int>[];

    for (int i = 1; i <= _preloadCount; i++) {
      int nextIndex;

      if (_isShuffleEnabled) {
        // For shuffle mode, we can't predict the next songs
        // So we preload a few near-future ones by index
        nextIndex = (_currentIndex + i) % _playlist.length;
      } else {
        nextIndex = (_currentIndex + i) % _playlist.length;
      }

      if (nextIndex < _playlist.length) {
        indices.add(nextIndex);
      }
    }

    return indices;
  }

  /// Handle playback completion
  Future<void> _handlePlaybackCompleted() async {
    if (_loopMode == LoopMode.one) {
      // Loop current track
      await _player.seek(Duration.zero);
      await _player.play();
    } else if (_loopMode == LoopMode.all ||
        (_currentIndex + 1) < _playlist.length) {
      // Continue to next track or loop playlist
      await skipToNext();
    } else if (_loopMode == LoopMode.all) {
      // Loop back to the beginning
      _currentIndex = 0;
      await _ensureTrackReady(0);
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    } else {
      // Playlist ended
      await _player.stop();
      notifyListeners();
    }
  }

  /// Clear cache and cleanup
  void clearCache() {
    _streamingService.clearExpiredCache();
    _preloadedIndices.clear();
    _imageCacheService.clearCache();
  }

  /// Preload album art images for better caching
  Future<void> _preloadImages() async {
    // Preload current track image
    if (_currentIndex < _playlist.length) {
      final currentTrack = _playlist[_currentIndex];
      if (currentTrack.thumbnailUrl != null) {
        _imageCacheService.preloadImage(currentTrack.thumbnailUrl!);
      }
    }

    // Preload upcoming track images
    final upcomingIndices = _getUpcomingIndices();
    for (final index in upcomingIndices.take(3)) {
      // Preload next 3 images
      if (index < _playlist.length) {
        final track = _playlist[index];
        if (track.thumbnailUrl != null) {
          _imageCacheService.preloadImage(track.thumbnailUrl!);
        }
      }
    }
  }

  /// Rebuild ConcatenatingAudioSource from the current playlist in order
  Future<void> _rebuildAudioSource({
    int? preferPlaylistIndex,
    bool preservePosition = true,
    int? requestId,
  }) async {
    // If called from a superseded load, abort early
    if (requestId != null && requestId != _loadRequestId) return;

    // Build children for ready tracks in playlist order
    final children = <AudioSource>[];
    final readyIndices = <int>[]; // Map from audio index to playlist index
    for (int i = 0; i < _playlist.length; i++) {
      final t = _playlist[i];
      if (t.isReady && t.streamUrl != null) {
        children.add(
          AudioSource.uri(
            Uri.parse(t.streamUrl!),
            tag: MediaItem(
              id: t.videoId,
              title: t.title,
              artist: t.artist,
              duration: t.duration,
              artUri: t.thumbnailUrl != null
                  ? Uri.tryParse(t.thumbnailUrl!)
                  : null,
              extras: {'videoId': t.videoId},
            ),
          ),
        );
        readyIndices.add(i);
      }
    }

    if (children.isEmpty) {
      // Nothing to set yet
      return;
    }

    final wasPlaying = _player.playing;
    final prevPosition = _player.position;
    final desiredPlaylistIndex = (preferPlaylistIndex ?? _currentIndex).clamp(
      0,
      _playlist.length - 1,
    );

    // Compute new audio index corresponding to desired playlist index
    int newAudioIndex = 0;
    if (_playlist[desiredPlaylistIndex].isReady &&
        _playlist[desiredPlaylistIndex].streamUrl != null) {
      newAudioIndex = _getAudioSourceIndex(desiredPlaylistIndex);
    } else {
      // If desired track not ready, pick the next available ready track after it
      int? fallbackPlaylistIndex;
      for (int i = desiredPlaylistIndex; i < _playlist.length; i++) {
        if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
          fallbackPlaylistIndex = i;
          break;
        }
      }
      fallbackPlaylistIndex ??= readyIndices.isNotEmpty
          ? readyIndices.first
          : 0;
      newAudioIndex = _getAudioSourceIndex(fallbackPlaylistIndex);
    }

    // Create and set the new audio source
    final newSource = ConcatenatingAudioSource(
      children: children,
      useLazyPreparation: true,
    );

    // Decide initial position: keep position only if staying on same playlist index and that track is ready
    final keepPosition =
        preservePosition &&
        desiredPlaylistIndex == _currentIndex &&
        _playlist[desiredPlaylistIndex].isReady;

    // Before applying, ensure this call hasn't been superseded
    if (requestId != null && requestId != _loadRequestId) return;

    await _player.setAudioSource(
      newSource,
      initialIndex: newAudioIndex.clamp(0, children.length - 1),
      initialPosition: keepPosition ? prevPosition : Duration.zero,
    );

    _audioSource = newSource;

    if (wasPlaying) {
      await _player.play();
    }
  }

  /// Dispose resources
  @override
  void dispose() {
    _currentTrackController.close();
    _trackInfoController.close();
    _player.dispose();
    _streamingService.dispose();
    isPreparing.dispose();
    super.dispose();
  }
}
