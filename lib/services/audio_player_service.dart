/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart' show Options;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/loading_progress_model.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/services/dio_client.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/services/settings_service.dart';

import '../isolate/playlist_worker.dart' show playlistWorkerEntry;

class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();
  final MusicStreamingService _streamingService = MusicStreamingService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  // Progressive incremental insertion state
  final Set<int> _materializedIndices = <int>{};
  int? _currentProgressiveWorkerReqId;
  Future<void> _insertionQueue = Future<void>.value();

  // Isolate support for heavy playlist building
  SendPort? _playlistWorkerSendPort;
  Isolate? _playlistWorker;
  ReceivePort?
  _playlistWorkerReceivePort; // retained so it isn't GC'd & can be closed on dispose
  int _playlistWorkerRequestCounter = 0;
  static const int _isolateThreshold = 80; // min tracks to offload
  bool enableProgressiveIsolate = true; // feature flag
  // New: enforce resolving all stream URLs before feeding the player
  bool resolveAllBeforeFeeding = true; // set true to guarantee full metadata
  final Duration _isolateOverallTimeout = const Duration(seconds: 6);
  Stopwatch? _currentLoadStopwatch;
  DateTime? _firstProgressAt;
  DateTime? _firstPlayableAt;
  int _lastProgressResolvedCount = 0;
  DateTime? _loadStartAt;

  // Debounced preparing state exposure
  bool _internalPreparing = false;
  Timer? _preparingDebounceTimer;

  // Progress tracking for playlist loading
  final ValueNotifier<LoadingProgress?> loadingProgress =
      ValueNotifier<LoadingProgress?>(null);

  Future<void> _initPlaylistWorker() async {
    if (_playlistWorkerSendPort != null) return; // already initialized
    final ReceivePort rp = ReceivePort();
    _playlistWorkerReceivePort = rp; // retain reference
    _playlistWorker = await Isolate.spawn(
      _playlistWorkerEntryPoint,
      rp.sendPort,
      debugName: 'playlist_worker',
      errorsAreFatal: false,
    );
    final c = Completer<SendPort>();
    rp.listen((message) {
      if (message is SendPort && !c.isCompleted) {
        c.complete(message);
        return;
      }
      if (message is Map && message.containsKey('requestId')) {
        final int reqId = message['requestId'] as int? ?? -1;
        final completer = _pendingWorkerRequests.remove(reqId);
        Map<String, dynamic>? typed;
        try {
          typed = Map<String, dynamic>.from(message);
          if (completer != null && !completer.isCompleted) {
            completer.complete(typed);
          }
        } catch (e, st) {
          if (completer != null && !completer.isCompleted) {
            completer.completeError(e, st);
          }
        }
        if (typed != null) {
          // Always handle worker messages (progress/done) even if a completer consumed it
          _handleWorkerMessage(typed);
        }
      }
    });
    _playlistWorkerSendPort = await c.future;
  }

  final Map<int, Completer<Map<String, dynamic>>> _pendingWorkerRequests = {};

  Future<Map<String, dynamic>?> _offloadBuildPlaylist(
    List<StreamingData> list,
    int requestId,
  ) async {
    try {
      await _initPlaylistWorker();
      final send = _playlistWorkerSendPort;
      if (send == null) return null;
      final int localReqId = ++_playlistWorkerRequestCounter;
      final completer = Completer<Map<String, dynamic>>();
      _pendingWorkerRequests[localReqId] = completer;
      // Prepare lightweight serializable track list
      final tracks = <Map<String, dynamic>>[];
      for (final t in list) {
        tracks.add({
          'videoId': t.videoId,
          'title': t.title,
          'artist': t.artist,
          'thumbnailUrl': t.thumbnailUrl,
          'durationMs': t.duration?.inMilliseconds,
          'streamUrl': t.streamUrl,
          'isLocal': t.isLocal,
          'isReady': t.isReady,
        });
      }
      // Use new combined build + resolve path so we can receive fully resolved items
      send.send({
        'cmd': 'buildAndResolve',
        'tracks': tracks,
        'requestId': localReqId,
        'quality': 'medium', // TODO: wire through user quality preference
      });
      final res = await completer.future.timeout(const Duration(seconds: 3));
      // Ignore if main load superseded meanwhile
      if (requestId != _loadRequestId) return null;
      return res;
    } catch (_) {
      return null; // fallback to main thread
    }
  }

  static void _playlistWorkerEntryPoint(SendPort sp) {
    playlistWorkerEntry(sp);
  }

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

  // Playlist fingerprint to detect identity changes quickly
  String? _playlistFingerprint;
  String? get playlistFingerprint => _playlistFingerprint;

  String _computeFingerprint(List<StreamingData> tracks) {
    if (tracks.isEmpty) return 'empty';
    final ids = <String>[];
    final take = tracks.length <= 6 ? tracks.length : 3;
    for (int i = 0; i < take; i++) {
      ids.add(tracks[i].videoId);
    }
    if (tracks.length > take) {
      for (int i = tracks.length - take; i < tracks.length; i++) {
        ids.add(tracks[i].videoId);
      }
    }
    final basis = '${tracks.length}|${ids.join(',')}';
    int hash = 0xcbf29ce484222325; // FNV-1a 64-bit basis
    const int prime = 0x100000001b3;
    for (final cu in basis.codeUnits) {
      hash ^= cu;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  // Current track stream controller
  final StreamController<StreamingData?> _currentTrackController =
      StreamController<StreamingData?>.broadcast();

  // Event-driven TrackInfo broadcaster (replaces periodic polling)
  final StreamController<TrackInfo> _trackInfoController =
      StreamController<TrackInfo>.broadcast();
  TrackInfo? _lastTrackInfo;
  DateTime _lastProgressEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // Constant durations used in throttling / delays
  static const Duration _progressThrottle = Duration(milliseconds: 250);
  static const Duration _significantProgressDelta = Duration(milliseconds: 200);

  // Loop mode string mapping (avoids switch allocation each emission)
  static const Map<LoopMode, String> _loopModeString = <LoopMode, String>{
    LoopMode.off: 'off',
    LoopMode.one: 'one',
    LoopMode.all: 'all',
  };

  // Lightweight derived snapshot stream (optional consumer optimization)
  Stream<PlaybackSnapshot> get playbackSnapshotStream => trackInfoStream.map(
    (t) => PlaybackSnapshot(
      videoId: t.track?.videoId,
      isPlaying: t.isPlaying,
      progress: t.progress,
    ),
  );

  // Expose preparation/loading state for UI skeletons
  final ValueNotifier<bool> isPreparing = ValueNotifier<bool>(false);

  // Concurrency guards
  int _loadRequestId = 0; // monotonically increasing id for load operations

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

    final String loopModeString = _loopModeString[loopMode] ?? 'off';

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
        now.difference(_lastProgressEmit) > _progressThrottle;
    final significantProgress =
        posDeltaMs >= _significantProgressDelta.inMilliseconds;

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

  /// Backwards compatible API: always forces full replace semantics.
  Future<void> loadPlaylist(
    List<StreamingData> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    String? sourceName,
    String sourceType = 'QUEUE',
  }) async {
    await replacePlaylist(
      tracks,
      initialIndex: initialIndex,
      autoPlay: autoPlay,
      sourceName: sourceName,
      sourceType: sourceType,
      force: true,
    );
  }

  /// Jump inside existing playlist.
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (index == _currentIndex) {
      if (!_player.playing) await _player.play();
      return;
    }
    await seek(Duration.zero, index: index);
  }

  /// Replace playlist only when identity changed (or force). Returns true if replaced.
  Future<bool> replacePlaylist(
    List<StreamingData> newTracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    String? sourceName,
    String sourceType = 'QUEUE',
    bool force = false,
  }) async {
    // Enforce global max queue size of 25, keeping the selected track inside the window
    List<StreamingData> cappedTracks;
    int cappedInitialIndex;
    if (newTracks.length > 25) {
      final total = newTracks.length;
      int start = initialIndex - 12; // aim to center selection
      if (start < 0) start = 0;
      if (start > total - 25) start = total - 25;
      final end = start + 25;
      cappedTracks = newTracks.sublist(start, end);
      cappedInitialIndex = initialIndex - start;
    } else {
      cappedTracks = newTracks;
      cappedInitialIndex = initialIndex.clamp(0, newTracks.length - 1);
    }

    final newFp = _computeFingerprint(cappedTracks);
    final same =
        !force && _playlistFingerprint != null && _playlistFingerprint == newFp;
    if (same) {
      if (cappedInitialIndex >= 0 && cappedInitialIndex < _playlist.length) {
        await jumpToIndex(cappedInitialIndex);
      }
      return false;
    }
    _playlistFingerprint = newFp;

    final int requestId = ++_loadRequestId;
    _setPreparing(true);
    try {
      _playlist = cappedTracks;
      _currentIndex = cappedInitialIndex;
      _materializedIndices.clear();
      _preloadedIndices.clear();
      _currentLoadStopwatch = Stopwatch()..start();
      _loadStartAt = DateTime.now();
      _firstProgressAt = null;
      _firstPlayableAt = null;
      _lastProgressResolvedCount = 0;
      _sourceName = sourceName;
      _sourceType = sourceType;

      // Keep progress tracking for telemetry but don't show it
      // Progress overlay has been disabled - songs stream in background
      loadingProgress.value = null;

      if (resolveAllBeforeFeeding) {
        await _resolveAllTracksThenBuild(
          requestId: requestId,
          autoPlay: autoPlay,
        );
      } else {
        // Original progressive/small playlist handling (unchanged)
        final bool largeAndProgressive =
            _playlist.length >= _isolateThreshold && enableProgressiveIsolate;

        if (!largeAndProgressive &&
            _currentIndex >= 0 &&
            _currentIndex < _playlist.length &&
            !_playlist[_currentIndex].isReady) {
          await _ensureTrackReady(_currentIndex, requestId: requestId);
          if (requestId != _loadRequestId) return true;
        }

        if (largeAndProgressive) {
          _cancelProgressiveBuild();
          final prefetchIndices = <int>{_currentIndex};
          if (_currentIndex + 1 < _playlist.length)
            prefetchIndices.add(_currentIndex + 1);
          if (_currentIndex + 2 < _playlist.length)
            prefetchIndices.add(_currentIndex + 2);
          final futures = <Future<void>>[];
          for (final i in prefetchIndices) {
            if (_playlist[i].isReady) continue;
            futures.add(() async {
              final r = await _streamingService.fetchStreamingData(
                _playlist[i].videoId,
                _getPreferredQuality(),
              );
              if (r != null) {
                final old = _playlist[i];
                _playlist[i] = old.copyWith(
                  streamUrl: r.streamUrl,
                  quality: r.quality,
                  cachedAt: r.cachedAt,
                  isAvailable: true,
                  title: old.title.isNotEmpty ? old.title : r.title,
                  artist: old.artist.isNotEmpty ? old.artist : r.artist,
                  duration: old.duration ?? r.duration,
                  thumbnailUrl: r.thumbnailUrl ?? old.thumbnailUrl,
                );
              }
            }());
          }
          if (futures.isNotEmpty) {
            await futures.first;
          }
          if (_playlist[_currentIndex].isReady &&
              _playlist[_currentIndex].streamUrl != null) {
            await _setMinimalSingleSource(_currentIndex, autoPlay: autoPlay);
            _firstPlayableAt ??= DateTime.now();
            if (autoPlay) {
              _setPreparing(false);
            }
          }
          // ignore: discarded_futures
          _startProgressiveIsolateBuild(
            requestId: requestId,
            autoPlay: autoPlay,
            initialFastMode: true,
          );
        } else {
          await _rebuildAudioSource(
            preferPlaylistIndex: _currentIndex,
            preservePosition: false,
            requestId: requestId,
          );
          if (autoPlay) {
            final readyAndMapped =
                _currentIndex < _playlist.length &&
                _playlist[_currentIndex].isReady &&
                _childToPlaylistIndex.contains(_currentIndex);
            if (readyAndMapped) {
              await _player.play();
            } else {
              await seek(Duration.zero, index: _currentIndex);
            }
          }

          final loadedCount = _playlist
              .where((t) => t.isReady && t.streamUrl != null)
              .length;
          loadingProgress.value = LoadingProgress(
            totalTracks: _playlist.length,
            loadedTracks: loadedCount,
            failedTracks: 0,
            phase: LoadingPhase.complete,
          );
        }
      }

      await _player.setLoopMode(_loopMode);
      if (!resolveAllBeforeFeeding) {
        final largeAndProgressive =
            _playlist.length >= _isolateThreshold && enableProgressiveIsolate;
        if (!largeAndProgressive || _childToPlaylistIndex.length > 1) {
          await _player.setShuffleModeEnabled(_isShuffleEnabled);
        }
      } else {
        await _player.setShuffleModeEnabled(_isShuffleEnabled);
      }

      final warmDelay = resolveAllBeforeFeeding
          ? const Duration(milliseconds: 350)
          : ((_playlist.length >= _isolateThreshold && enableProgressiveIsolate)
                ? const Duration(milliseconds: 1000)
                : const Duration(milliseconds: 350));
      Future.delayed(warmDelay, () {
        if (requestId != _loadRequestId) return;
        _preloadUpcomingSongs();
        _warmNextConnection();
        _preloadImages();
        _warmPlaylistStreamingUrls();
      });

      _currentTrackController.add(currentTrack);
      _emitTrackInfo(force: true);
      notifyListeners();
      return true;
    } finally {
      if (requestId == _loadRequestId) {
        _setPreparing(false);

        // Clear or complete progress after a delay to allow UI to show completion
        if (loadingProgress.value != null &&
            !loadingProgress.value!.isComplete) {
          final loadedCount = _playlist
              .where((t) => t.isReady && t.streamUrl != null)
              .length;
          loadingProgress.value = LoadingProgress(
            totalTracks: _playlist.length,
            loadedTracks: loadedCount,
            failedTracks: 0,
            phase: LoadingPhase.complete,
          );
        }

        _emitPerfLog(
          'finalizeLoad',
          extra: {
            'playlistSize': _playlist.length,
            'progressive':
                _playlist.length >= _isolateThreshold &&
                enableProgressiveIsolate,
            'fingerprint': _playlistFingerprint,
            'largeFastPath':
                _playlist.length >= _isolateThreshold &&
                enableProgressiveIsolate,
          },
        );
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

  // Resolve all tracks' stream URLs and metadata before building audio source
  Future<void> _resolveAllTracksThenBuild({
    required int requestId,
    required bool autoPlay,
  }) async {
    final quality = _getPreferredQuality();
    // Resolve in parallel with existing service limits
    final futures = <Future<void>>[];
    for (int i = 0; i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) continue;
      final idx = i;
      futures.add(() async {
        final r = await _streamingService.fetchStreamingData(
          _playlist[idx].videoId,
          quality,
        );
        if (r != null) {
          final old = _playlist[idx];
          _playlist[idx] = old.copyWith(
            streamUrl: r.streamUrl,
            quality: r.quality,
            cachedAt: r.cachedAt,
            isAvailable: true,
            title: old.title.isNotEmpty ? old.title : r.title,
            artist: old.artist.isNotEmpty ? old.artist : r.artist,
            duration: old.duration ?? r.duration,
            thumbnailUrl: r.thumbnailUrl ?? old.thumbnailUrl,
          );
        }
      }());
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    if (requestId != _loadRequestId) return;

    // Build children from fully-resolved playlist
    final children = <AudioSource>[];
    final readyIndices = <int>[];
    for (int i = 0; i < _playlist.length; i++) {
      final t = _playlist[i];
      if (!t.isReady || t.streamUrl == null) continue;
      children.add(
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
      readyIndices.add(i);
    }

    if (children.isEmpty) return;

    _childToPlaylistIndex = List<int>.from(readyIndices);
    final initChildIndex = _getAudioSourceIndex(
      _currentIndex,
    ).clamp(0, children.length - 1);

    final bool wasShuffled = _player.shuffleModeEnabled;
    if (wasShuffled) await _player.setShuffleModeEnabled(false);
    await _player.setAudioSources(
      children,
      initialIndex: initChildIndex,
      initialPosition: Duration.zero,
    );
    if (wasShuffled) await _player.setShuffleModeEnabled(true);
    if (autoPlay) await _player.play();
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
    if (index != null) {
      if (index < 0 || index >= _playlist.length) return;
      // Ensure streaming info ready if needed
      await _ensureTrackReady(index);
      if (!_playlist[index].isReady) return;
      // If mapping doesn't include the target yet, rebuild preserving position
      if (!_childToPlaylistIndex.contains(index)) {
        await _rebuildAudioSource(
          preferPlaylistIndex: _currentIndex,
          preservePosition: true,
        );
      }
      final childIndex = _childToPlaylistIndex.indexOf(index);
      if (childIndex < 0) return; // still not mapped
      final effectiveIndex = _childIndexToSequenceIndex(childIndex);
      try {
        await _player.seek(position, index: effectiveIndex);
      } catch (_) {
        // Fallback to simple seek
        await _player.seek(position);
      }
      if (index != _currentIndex) {
        _currentIndex = index;
        _currentTrackController.add(currentTrack);
        _emitTrackInfo(force: true);
        notifyListeners();
        _preloadImages();
      }
      return;
    }
    // Seek within current track only
    await _player.seek(position);
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

  /// Map playlist index -> child index in the current audio source list
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
      debugPrint(
        'Batch processing completed: ${result.successCount}/${result.totalCount} in ${result.processingTime.inMilliseconds}ms',
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
        debugPrint('Warm-up failed: $e');
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

  /// Rebuild player sources from the current playlist in order
  Future<void> _rebuildAudioSource({
    int? preferPlaylistIndex,
    bool preservePosition = true,
    int? requestId,
  }) async {
    // If called from a superseded load, abort early
    if (requestId != null && requestId != _loadRequestId) return;

    List<AudioSource> children = <AudioSource>[];
    List<int> readyIndices = <int>[];

    if (_playlist.length >= _isolateThreshold) {
      final result = await _offloadBuildPlaylist(
        _playlist,
        requestId ?? _loadRequestId,
      );
      if (result != null) {
        // New response format: type=resolveDone, resolved:[{index,...}], failed:[...]
        final resolved = (result['resolved'] as List<dynamic>? ?? const []);
        for (final r in resolved) {
          if (r is Map<String, dynamic>) {
            final idx = r['index'] as int?;
            final streamUrl = r['streamUrl'] as String?;
            if (idx == null || streamUrl == null) continue;
            if (idx < 0 || idx >= _playlist.length) continue;
            final original = _playlist[idx];
            final updated = original.copyWith(
              streamUrl: streamUrl,
              isAvailable: true,
              title: r['title'] as String? ?? original.title,
              artist: r['artist'] as String? ?? original.artist,
              duration: (r['durationMs'] is int)
                  ? Duration(milliseconds: r['durationMs'] as int)
                  : original.duration,
              // thumbnail not in copyWith signature differently; use copyWith
              thumbnailUrl:
                  r['thumbnailUrl'] as String? ?? original.thumbnailUrl,
            );
            _playlist[idx] = updated; // mutate list entry
          }
        }
        // Build children from updated playlist
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
      }
    }

    if (children.isEmpty) {
      // Fallback to main isolate build
      children = <AudioSource>[];
      readyIndices = <int>[];
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
      await _player.setAudioSources(
        children,
        initialIndex: newChildIndex.clamp(0, children.length - 1),
        initialPosition: keepPosition ? prevPosition : Duration.zero,
      );
    } on PlayerException catch (e) {
      // Auto-recovery: attempt to refresh the failing track's URL and retry once
      if (kDebugMode) {
        debugPrint('PlayerException during setAudioSource: ${e.message}');
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
          await _player.setAudioSources(
            retryChildren,
            initialIndex: _getAudioSourceIndex(
              _currentIndex,
            ).clamp(0, retryChildren.length - 1),
            initialPosition: keepPosition ? prevPosition : Duration.zero,
          );
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

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
    // Cleanly tear down isolate *only* when service is disposed (app shutdown)
    try {
      _playlistWorkerReceivePort?.close();
    } catch (_) {}
    try {
      _playlistWorker?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _playlistWorkerReceivePort = null;
    _playlistWorkerSendPort = null;
    _playlistWorker = null;
    _currentTrackController.close();
    _trackInfoController.close();
    _player.dispose();
    _streamingService.dispose();
    isPreparing.dispose();
    loadingProgress.dispose();
    super.dispose();
  }

  void _setMinimalChildMapping(int playlistIndex) {
    _childToPlaylistIndex = [playlistIndex];
  }

  Future<void> _setMinimalSingleSource(
    int playlistIndex, {
    required bool autoPlay,
  }) async {
    final t = _playlist[playlistIndex];
    if (!t.isReady || t.streamUrl == null) return;
    final uri = _toPlayableUri(t.streamUrl!, isLocal: t.isLocal);
    _setMinimalChildMapping(playlistIndex);
    await _player.setAudioSource(
      AudioSource.uri(
        uri,
        tag: MediaItem(
          id: t.videoId,
          title: t.title,
          artist: t.artist,
          duration: t.duration,
          artUri: t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
          extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
        ),
      ),
      preload: true,
    );
    if (autoPlay) {
      await _player.play();
    }
  }

  // Serialize insertion operations to avoid race conditions with just_audio internal queue
  void _enqueueInsertion(Future<void> Function() op) {
    _insertionQueue = _insertionQueue.then((_) => op()).catchError((_) {});
  }

  Future<void> _insertResolvedTrack(int playlistIndex) async {
    // Simplified: rebuild full source to include newly ready track
    if (playlistIndex < 0 || playlistIndex >= _playlist.length) return;
    if (!(_playlist[playlistIndex].isReady &&
        _playlist[playlistIndex].streamUrl != null))
      return;
    await _rebuildAudioSource(preservePosition: true);
    _materializedIndices.add(playlistIndex);
  }

  void _handleWorkerMessage(Map<String, dynamic> message) {
    final type = message['type'];
    if (type != 'progress' && type != 'done')
      return; // only handle progressive events
    // Guard against superseded loads
    final reqId = message['requestId'] as int?;
    if (reqId == null || reqId != _currentProgressiveWorkerReqId) return;
    if (_playlist.isEmpty) return;
    final resolved = (message['resolved'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final failed = (message['failed'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    // Update loading progress for UI
    _updateLoadingProgress(resolved, failed, type == 'done');

    if (resolved.isEmpty) return;
    // Update internal playlist entries & schedule insertions for newly playable tracks
    for (final r in resolved) {
      final idx = r['index'] as int?;
      final streamUrl = r['streamUrl'] as String?;
      if (idx == null || streamUrl == null) continue;
      if (idx < 0 || idx >= _playlist.length) continue;
      final original = _playlist[idx];
      final updated = original.copyWith(
        streamUrl: streamUrl,
        title: (r['title'] as String?) ?? original.title,
        artist: (r['artist'] as String?) ?? original.artist,
        duration: (r['durationMs'] is int)
            ? Duration(milliseconds: r['durationMs'] as int)
            : original.duration,
        thumbnailUrl: (r['thumbnailUrl'] as String?) ?? original.thumbnailUrl,
        isAvailable: true,
      );
      _playlist[idx] = updated;
      // Enqueue insertion (serialized) for newly ready tracks not yet materialized
      if (!_materializedIndices.contains(idx)) {
        _enqueueInsertion(() => _insertResolvedTrack(idx));
      }
    }
    _lastProgressResolvedCount =
        resolved.length; // for perf log (cumulative list length from worker)
    _firstProgressAt ??= DateTime.now();
    if (_firstPlayableAt == null && _materializedIndices.isNotEmpty) {
      _firstPlayableAt = DateTime.now();
    }
    if (type == 'done') {
      _emitPerfLog(
        'progressiveDone',
        extra: {
          'totalResolved': resolved.length,
          'playlistSize': _playlist.length,
        },
      );
    } else {
      _emitPerfLog(
        'progress',
        extra: {
          'resolved': resolved.length,
          'materialized': _materializedIndices.length,
        },
      );
    }
  }

  void _updateLoadingProgress(
    List<Map<String, dynamic>> resolved,
    List<Map<String, dynamic>> failed,
    bool isDone,
  ) {
    // Build track statuses map from the current state of the playlist
    final statuses = <String, TrackLoadStatus>{};
    int loadedCount = 0;
    int failedCount = 0;

    // Create sets for quick lookup
    final resolvedVideoIds = <String>{};
    for (final track in resolved) {
      final videoId = track['videoId'] as String?;
      if (videoId != null) {
        resolvedVideoIds.add(videoId);
      }
    }

    final failedVideoIds = <String>{};
    for (final track in failed) {
      final videoId = track['videoId'] as String?;
      if (videoId != null) {
        failedVideoIds.add(videoId);
      }
    }

    // Iterate through playlist and determine status for each track
    for (final track in _playlist) {
      if (resolvedVideoIds.contains(track.videoId)) {
        statuses[track.videoId] = TrackLoadStatus.loaded;
        loadedCount++;
      } else if (failedVideoIds.contains(track.videoId)) {
        statuses[track.videoId] = TrackLoadStatus.failed;
        failedCount++;
      } else if (track.isReady && track.streamUrl != null) {
        // Track was already ready (e.g., from cache)
        statuses[track.videoId] = TrackLoadStatus.loaded;
        loadedCount++;
      } else {
        statuses[track.videoId] = TrackLoadStatus.pending;
      }
    }

    // Update progress
    loadingProgress.value = LoadingProgress(
      totalTracks: _playlist.length,
      loadedTracks: loadedCount,
      failedTracks: failedCount,
      phase: isDone ? LoadingPhase.complete : LoadingPhase.loading,
      trackStatuses: statuses,
    );

    notifyListeners();
  }

  void _setPreparing(bool value) {
    if (value == _internalPreparing) return;
    _internalPreparing = value;
    _preparingDebounceTimer?.cancel();
    if (value) {
      _preparingDebounceTimer = Timer(const Duration(milliseconds: 120), () {
        if (_internalPreparing) {
          isPreparing.value = true;
        }
      });
    } else {
      isPreparing.value = false;
    }
  }

  void _emitPerfLog(String phase, {Map<String, Object?> extra = const {}}) {
    if (!kDebugMode) return;
    final map = <String, Object?>{
      'phase': phase,
      'elapsedMs': _currentLoadStopwatch?.elapsedMilliseconds,
      'firstProgressMs': _firstProgressAt == null || _loadStartAt == null
          ? null
          : _firstProgressAt!.difference(_loadStartAt!).inMilliseconds,
      'firstPlayableMs': _firstPlayableAt == null || _loadStartAt == null
          ? null
          : _firstPlayableAt!.difference(_loadStartAt!).inMilliseconds,
      'resolvedCount': _lastProgressResolvedCount,
      ...extra,
    };
    debugPrint('[perf][playlistLoad] ${map.toString()}');
  }

  Future<void> _startProgressiveIsolateBuild({
    required int requestId,
    required bool autoPlay,
    bool initialFastMode = false,
  }) async {
    try {
      await _initPlaylistWorker();
      final send = _playlistWorkerSendPort;
      if (send == null) return;
      final int localReqId = ++_playlistWorkerRequestCounter;
      _currentProgressiveWorkerReqId = localReqId;
      final completer = Completer<void>();
      _pendingWorkerRequests[localReqId] =
          Completer<Map<String, dynamic>>(); // dummy to leverage existing map
      final tracks = <Map<String, dynamic>>[];
      for (final t in _playlist) {
        tracks.add({
          'videoId': t.videoId,
          'title': t.title,
          'artist': t.artist,
          'thumbnailUrl': t.thumbnailUrl,
          'durationMs': t.duration?.inMilliseconds,
          'streamUrl': t.streamUrl,
          'isLocal': t.isLocal,
          'isReady': t.isReady,
        });
      }
      final startTime = DateTime.now();
      send.send({
        'cmd': 'buildAndResolve',
        'progressive': true,
        'tracks': tracks,
        'requestId': localReqId,
        'quality': 'medium',
        'priorityIndex': _currentIndex,
        'batchSize': initialFastMode ? 3 : 6,
        'concurrency': 4,
      });

      // Listen for progress via existing receive port listener path
      // We piggyback on rp listener which will put messages through the completer remove logic.
      // We'll intercept messages by extending listener logic (below) – add handler here via microtask polling.

      // Polling approach: not ideal but minimal invasive (we can restructure later)
      () async {
        final timeoutAt = startTime.add(_isolateOverallTimeout);
        while (DateTime.now().isBefore(timeoutAt)) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (requestId != _loadRequestId) return; // superseded
          // Break if final done observed
          if (_lastProgressResolvedCount >= _playlist.length) break;
        }
        if (!completer.isCompleted) completer.complete();
      }();
      await completer.future;
    } catch (_) {
      // fallback: rebuild synchronously later if needed
    }
  }

  void _cancelProgressiveBuild() {
    final send = _playlistWorkerSendPort;
    final prev = _currentProgressiveWorkerReqId;
    if (send != null && prev != null) {
      try {
        send.send({'cmd': 'cancel', 'requestId': prev});
      } catch (_) {}
    }
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

/// Immutable lightweight snapshot for simple UI consumers that only need
/// video id, playing state and progress. Does not alter existing data flow.
class PlaybackSnapshot {
  final String? videoId;
  final bool isPlaying;
  final double progress; // 0.0 - 1.0
  const PlaybackSnapshot({
    required this.videoId,
    required this.isPlaying,
    required this.progress,
  });
}
