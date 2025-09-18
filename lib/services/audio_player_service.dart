/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart' show Options;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/services/dio_client.dart';
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

  // Maintain mapping from audio child index -> playlist index for the current source
  List<int> _childToPlaylistIndex = <int>[];

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
        // Map effective sequence index back to playlist index (shuffle-aware)
        final newIndex = _sequenceIndexToPlaylistIndex(audioIndex);
        if (newIndex != _currentIndex) {
          _currentIndex = newIndex;
          _currentTrackController.add(currentTrack);
          _emitTrackInfo(force: true);
          notifyListeners();
          _preloadUpcomingSongs();
          _warmNextConnection();
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

      // Proactively start preparing the immediate next track so pressing
      // "Next" from the first song switches quickly.
      if (_playlist.length > 1) {
        final nextIdx = (_currentIndex + 1) % _playlist.length;
        // Fire-and-forget; resolve streaming data without triggering a
        // rebuild that could affect the current track's position.
        // ignore: discarded_futures
        _streamingService
            .fetchStreamingData(
              _playlist[nextIdx].videoId,
              _getPreferredQuality(),
            )
            .then((result) async {
              if (result != null) {
                // Merge streaming details into the playlist but avoid a rebuild.
                final old = _playlist[nextIdx];
                _playlist[nextIdx] = old.copyWith(
                  title: old.title.isNotEmpty ? old.title : result.title,
                  artist: old.artist.isNotEmpty ? old.artist : result.artist,
                  thumbnailUrl: result.thumbnailUrl ?? old.thumbnailUrl,
                  duration: old.duration ?? result.duration,
                  streamUrl: result.streamUrl,
                  quality: result.quality,
                  cachedAt: result.cachedAt,
                  isAvailable: result.isAvailable,
                );
                // Ensure the next track is present in the audio source mapping
                // so users can skip immediately.
                if (!_childToPlaylistIndex.contains(nextIdx)) {
                  await _rebuildAudioSource(
                    preferPlaylistIndex: _currentIndex,
                    preservePosition: true,
                    requestId: requestId,
                  );
                }
              }
            });
      }

      // Apply shuffle/loop preferences before starting playback
      await _player.setLoopMode(_loopMode);
      await _player.setShuffleModeEnabled(_isShuffleEnabled);

      if (autoPlay) {
        // Seek to the selected index and start playback
        await seek(Duration.zero, index: _currentIndex);
      }

      // Preload upcoming tracks
      _preloadUpcomingSongs();
      _warmNextConnection();

      // Preload album art images for current and upcoming tracks
      _preloadImages();

      // Also warm the entire playlist's streaming URLs in background
      // to make arbitrary queue taps instant
      _warmPlaylistStreamingUrls();

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

  /// Issue a tiny byte-range request to the next track to warm DNS/TLS/CDN.
  void _warmNextConnection() {
    () async {
      try {
        final upcoming = _getUpcomingIndices();
        if (upcoming.isEmpty) return;
        final idx = upcoming.first;
        if (idx < 0 || idx >= _playlist.length) return;
        final t = _playlist[idx];
        if (!t.isReady || t.isLocal || t.streamUrl == null) return;
        final url = t.streamUrl!;
        if (!(url.startsWith('http://') || url.startsWith('https://'))) return;
        await DioClient.instance.get(
          url,
          options: Options(
            headers: const {'Range': 'bytes=0-0'},
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            validateStatus: (s) => s != null && (s < 400 || s == 416),
          ),
        );
      } catch (_) {
        // best-effort only
      }
    }();
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
        // Ensure the target track is ready and included in the audio source
        await _ensureTrackReady(index);

        // Verify readiness
        if (!_playlist[index].isReady) {
          if (kDebugMode) {
            print('Warning: Track at index $index is not ready for playback');
          }
          return;
        }

        // If mapping doesn't yet include this playlist index, rebuild once more
        if (!_childToPlaylistIndex.contains(index)) {
          await _rebuildAudioSource(
            preferPlaylistIndex: _currentIndex,
            preservePosition: true,
          );
        }

        // If still not included, abort gracefully (avoid seeking wrong track)
        final childIndex = _childToPlaylistIndex.indexOf(index);
        if (_audioSource == null || childIndex < 0) {
          if (kDebugMode) {
            print('Seek aborted: target index $index not in audio source yet');
          }
          return;
        }

        // Compute effective (sequence) index under current shuffle state
        final effectiveIndex = _childIndexToSequenceIndex(childIndex);

        try {
          await _player.seek(position, index: effectiveIndex);
          await _player.play(); // Ensure playback starts

          // Update current metadata/UI only after a successful seek
          if (index != _currentIndex) {
            _currentIndex = index;
            _currentTrackController.add(currentTrack);
            _emitTrackInfo(force: true);
            notifyListeners();

            // Preload images for the new current track and upcoming tracks
            _preloadImages();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error seeking to effective index $effectiveIndex: $e');
          }
          // Fallback: try to play without seeking to specific index
          await _player.play();
        }
      } finally {
        isPreparing.value = false;
      }
    }
  }

  /// Skip to next track
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;

    int nextIndex;
    if (_isShuffleEnabled && _childToPlaylistIndex.isNotEmpty) {
      final seqLen = _childToPlaylistIndex.length;
      final currentSeq =
          _player.currentIndex ??
          _childIndexToSequenceIndex(_getAudioSourceIndex(_currentIndex));
      final nextSeq = (currentSeq + 1) % seqLen;
      nextIndex = _sequenceIndexToPlaylistIndex(nextSeq);
    } else {
      nextIndex = (_currentIndex + 1) % _playlist.length;
    }

    // Prefer immediate movement among currently ready children when possible.
    final hasMultipleReadyChildren = _childToPlaylistIndex.length > 1;

    final beforeIndex = _currentIndex;
    await seek(Duration.zero, index: nextIndex);

    // If target wasn’t ready and nothing changed, try advancing to next ready child.
    if (_currentIndex == beforeIndex && hasMultipleReadyChildren) {
      try {
        await _player.seekToNext();
      } catch (_) {
        // no-op
      }
    }
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;

    int prevIndex;
    if (_isShuffleEnabled && _childToPlaylistIndex.isNotEmpty) {
      final seqLen = _childToPlaylistIndex.length;
      final currentSeq =
          _player.currentIndex ??
          _childIndexToSequenceIndex(_getAudioSourceIndex(_currentIndex));
      final prevSeq = (currentSeq - 1 + seqLen) % seqLen;
      prevIndex = _sequenceIndexToPlaylistIndex(prevSeq);
    } else {
      prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    }

    final hasMultipleReadyChildren = _childToPlaylistIndex.length > 1;

    final beforeIndex = _currentIndex;
    await seek(Duration.zero, index: prevIndex);

    if (_currentIndex == beforeIndex && hasMultipleReadyChildren) {
      try {
        await _player.seekToPrevious();
      } catch (_) {
        // no-op
      }
    }
  }

  /// Get indices of upcoming tracks to preload
  List<int> _getUpcomingIndices() {
    final indices = <int>[];

    if (_playlist.isEmpty) return indices;

    if (_isShuffleEnabled && _childToPlaylistIndex.isNotEmpty) {
      // Preload according to shuffle sequence order
      final seqLen = _childToPlaylistIndex.length;
      final currentSeq =
          _player.currentIndex ??
          _childIndexToSequenceIndex(_getAudioSourceIndex(_currentIndex));
      for (int i = 1; i <= _preloadCount; i++) {
        final seqIndex = (currentSeq + i) % seqLen;
        final playlistIndex = _sequenceIndexToPlaylistIndex(seqIndex);
        if (playlistIndex >= 0 && playlistIndex < _playlist.length) {
          indices.add(playlistIndex);
        }
      }
    } else {
      // Linear order when not shuffled
      for (int i = 1; i <= _preloadCount; i++) {
        final nextIndex = (_currentIndex + i) % _playlist.length;
        indices.add(nextIndex);
      }
    }

    return indices;
  }

  /// Map effective sequence index (shuffle-aware) -> playlist index
  int _sequenceIndexToPlaylistIndex(int sequenceIndex) {
    if (sequenceIndex < 0) return _currentIndex;
    // Resolve child index from sequence index when shuffled
    int childIndex = sequenceIndex;
    if (_player.shuffleModeEnabled) {
      final shuffle = _player.shuffleIndices;
      if (sequenceIndex >= shuffle.length) {
        return _currentIndex;
      }
      childIndex = shuffle[sequenceIndex];
    }
    if (childIndex < 0 || childIndex >= _childToPlaylistIndex.length) {
      return _currentIndex;
    }
    return _childToPlaylistIndex[childIndex];
  }

  /// Map playlist index -> child index in ConcatenatingAudioSource
  int _playlistIndexToChildIndex(int playlistIndex) {
    if (playlistIndex < 0 || playlistIndex >= _playlist.length) return -1;
    // Use mapping if available
    if (_childToPlaylistIndex.isNotEmpty) {
      final childIndex = _childToPlaylistIndex.indexOf(playlistIndex);
      return childIndex; // may be -1 if not ready/not present
    }
    // Fallback to counting ready tracks (should rarely happen)
    int audioIndex = 0;
    for (int i = 0; i < playlistIndex && i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
        audioIndex++;
      }
    }
    return audioIndex;
  }

  /// Map child index -> effective sequence index under current shuffle
  int _childIndexToSequenceIndex(int childIndex) {
    if (!_player.shuffleModeEnabled) return childIndex;
    final shuffle = _player.shuffleIndices;
    final seqIndex = shuffle.indexOf(childIndex);
    return seqIndex >= 0 ? seqIndex : childIndex;
  }

  /// Get the index in the audio source for a playlist index (child index)
  int _getAudioSourceIndex(int playlistIndex) {
    if (playlistIndex < 0 || playlistIndex >= _playlist.length) {
      return 0; // Fallback to first track
    }

    // First try mapping built during _rebuildAudioSource
    final mapped = _playlistIndexToChildIndex(playlistIndex);
    if (mapped >= 0) return mapped;

    // If the target track itself is not ready, attempt to find nearest ready
    for (int i = playlistIndex; i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
        final m = _playlistIndexToChildIndex(i);
        if (m >= 0) return m;
      }
    }
    for (int i = playlistIndex - 1; i >= 0; i--) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) {
        final m = _playlistIndexToChildIndex(i);
        if (m >= 0) return m;
      }
    }

    return 0; // Fallback
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
          // Always prefer staying on the current playing index to avoid
          // unexpected jumps when preparing other tracks in the background.
          preferPlaylistIndex: _currentIndex,
          preservePosition: true,
          requestId: requestId,
        );
      }
    } else {
      // Track is already ready but may not have been added to the audio source yet.
      // If the mapping does not contain this playlist index, rebuild to include it.
      if (!_childToPlaylistIndex.contains(index)) {
        await _rebuildAudioSource(
          preferPlaylistIndex: _currentIndex,
          preservePosition: true,
          requestId: requestId,
        );
      }
    }
  }

  /// Warm up streaming URLs for the whole playlist in the background
  Future<void> _warmPlaylistStreamingUrls() async {
    try {
      // Collect all tracks that aren't ready yet
      final pending = _playlist
          .where((t) => !t.isReady || t.streamUrl == null)
          .map((t) => t.videoId)
          .toList();
      if (pending.isEmpty) return;

      // Batch process all pending; helper will update playlist and rebuild once
      await _batchProcessTracks(pending);
    } catch (e) {
      if (kDebugMode) {
        print('Warm-up failed: $e');
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
    final readyIndices =
        <int>[]; // Map from child (audio) index to playlist index
    for (int i = 0; i < _playlist.length; i++) {
      final t = _playlist[i];
      if (t.isReady && t.streamUrl != null) {
        final uri = _toPlayableUri(t.streamUrl!, isLocal: t.isLocal);
        children.add(
          AudioSource.uri(
            uri,
            tag: MediaItem(
              id: t.videoId,
              title: t.title,
              artist: t.artist,
              duration: t.duration,
              artUri: t.thumbnailUrl != null
                  ? Uri.tryParse(t.thumbnailUrl!)
                  : null,
              extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
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

    // Update mapping for later conversions
    _childToPlaylistIndex = List<int>.from(readyIndices);

    final wasPlaying = _player.playing;
    final prevPosition = _player.position;
    final desiredPlaylistIndex = (preferPlaylistIndex ?? _currentIndex).clamp(
      0,
      _playlist.length - 1,
    );

    // Compute new child index corresponding to desired playlist index
    int newChildIndex;
    if (_playlist[desiredPlaylistIndex].isReady &&
        _playlist[desiredPlaylistIndex].streamUrl != null) {
      newChildIndex = _getAudioSourceIndex(desiredPlaylistIndex);
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
      newChildIndex = _getAudioSourceIndex(fallbackPlaylistIndex);
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

    // To guarantee initial index selects the intended child regardless of shuffle,
    // temporarily disable shuffle, set source with child index, then restore shuffle mode.
    final bool wasShuffled = _player.shuffleModeEnabled;
    if (wasShuffled) {
      await _player.setShuffleModeEnabled(false);
    }

    try {
      await _player.setAudioSource(
        newSource,
        initialIndex: newChildIndex.clamp(0, children.length - 1),
        initialPosition: keepPosition ? prevPosition : Duration.zero,
      );
    } on PlayerException catch (e) {
      // Auto-recovery: attempt to refresh the failing track's URL and retry once
      if (kDebugMode) {
        print('PlayerException during setAudioSource: ${e.message}');
      }
      final failingPlaylistIndex = _childToPlaylistIndex.isNotEmpty
          ? _childToPlaylistIndex[newChildIndex.clamp(
              0,
              _childToPlaylistIndex.length - 1,
            )]
          : _currentIndex;
      final refreshed = await _streamingService.refreshStreamingData(
        _playlist[failingPlaylistIndex].videoId,
        _getPreferredQuality(),
      );
      if (refreshed != null) {
        final old = _playlist[failingPlaylistIndex];
        _playlist[failingPlaylistIndex] = old.copyWith(
          streamUrl: refreshed.streamUrl,
          cachedAt: refreshed.cachedAt,
          quality: refreshed.quality,
          isAvailable: refreshed.isAvailable,
          title: old.title.isNotEmpty ? old.title : refreshed.title,
          artist: old.artist.isNotEmpty ? old.artist : refreshed.artist,
          thumbnailUrl: refreshed.thumbnailUrl ?? old.thumbnailUrl,
          duration: old.duration ?? refreshed.duration,
        );

        // Rebuild children for ready tracks again
        final retryChildren = <AudioSource>[];
        final retryReadyIndices = <int>[];
        for (int i = 0; i < _playlist.length; i++) {
          final t = _playlist[i];
          if (t.isReady && t.streamUrl != null) {
            retryChildren.add(
              AudioSource.uri(
                _toPlayableUri(t.streamUrl!, isLocal: t.isLocal),
                tag: MediaItem(
                  id: t.videoId,
                  title: t.title,
                  artist: t.artist,
                  duration: t.duration,
                  artUri: t.thumbnailUrl != null
                      ? Uri.tryParse(t.thumbnailUrl!)
                      : null,
                  extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
                ),
              ),
            );
            retryReadyIndices.add(i);
          }
        }

        if (retryChildren.isNotEmpty) {
          _childToPlaylistIndex = List<int>.from(retryReadyIndices);
          final retrySource = ConcatenatingAudioSource(
            children: retryChildren,
            useLazyPreparation: true,
          );
          await _player.setAudioSource(
            retrySource,
            initialIndex: _getAudioSourceIndex(
              _currentIndex,
            ).clamp(0, retryChildren.length - 1),
            initialPosition: keepPosition ? prevPosition : Duration.zero,
          );
          _audioSource = retrySource;
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    _audioSource = newSource;

    // Restore shuffle state
    if (wasShuffled) {
      await _player.setShuffleModeEnabled(true);
    }

    if (wasPlaying) {
      await _player.play();
    }
  }

  Uri _toPlayableUri(String urlOrPath, {bool isLocal = false}) {
    if (isLocal) {
      final file = File(urlOrPath);
      return Uri.file(file.path);
    }
    // If it looks like a file path, prefer file URI
    if (urlOrPath.startsWith('/') || urlOrPath.contains('\\')) {
      return Uri.file(urlOrPath);
    }
    return Uri.parse(urlOrPath);
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

  /// Handle playback completion
  Future<void> _handlePlaybackCompleted() async {
    if (_playlist.isEmpty) {
      await _player.stop();
      notifyListeners();
      return;
    }

    if (_loopMode == LoopMode.one) {
      // Loop current track
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    if (_loopMode == LoopMode.all) {
      // Move to next according to current shuffle/order
      await skipToNext();
      return;
    }

    // No loop: if there is a next track, play it; otherwise stop
    final hasNext = _currentIndex < _playlist.length - 1;
    if (hasNext || _isShuffleEnabled) {
      await skipToNext();
    } else {
      await _player.stop();
      notifyListeners();
    }
  }

  /// Clear media-related caches (images and expired stream URLs)
  void clearCache() {
    try {
      _imageCacheService.clearCache();
    } catch (_) {}
    try {
      _streamingService.clearExpiredCache();
    } catch (_) {}
  }
}
