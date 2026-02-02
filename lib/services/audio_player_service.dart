/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart' show Options;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sautifyv2/db/continue_listening_store.dart';
import 'package:sautifyv2/db/library_store.dart';
import 'package:sautifyv2/db/metadata_overrides_store.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/loading_progress_model.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/models/streaming_resolver_preference.dart';
import 'package:sautifyv2/models/track_info.dart';
import 'package:sautifyv2/services/dio_client.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:sautifyv2/services/settings_service.dart';
import 'package:sautifyv2/services/ytmusic_service.dart';

import '../isolate/playlist_worker.dart' show playlistWorkerEntry;

class AudioPlayerService extends ChangeNotifier {
  static AudioPlayerService? _instance;
  factory AudioPlayerService() => _instance ??= AudioPlayerService._internal();

  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer _player;

  AudioPlayerService._internal() {
    // Always use AudioPipeline (and Equalizer) since MediaKit is removed
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [_equalizer, _loudnessEnhancer],
      ),
    );
    _applyEqualizerSettings();
  }

  Future<void> _applyEqualizerSettings() async {
    final settings = SettingsService();
    if (!settings.isReady) {
      await settings.init();
    }

    // Check if current track is local
    bool isLocal = false;
    if (_playlist.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _playlist.length) {
      isLocal = _playlist[_currentIndex].isLocal;
    }

    // Apply speed and pitch safely
    try {
      if (isLocal) {
        // Reset to defaults for local files to avoid codec issues
        if (_player.speed != 1.0) await _player.setSpeed(1.0);
        if (_player.pitch != 1.0) await _player.setPitch(1.0);
        if (_player.skipSilenceEnabled) {
          await _player.setSkipSilenceEnabled(false);
        }
      } else {
        if (settings.defaultPlaybackSpeed != 1.0) {
          await _player.setSpeed(settings.defaultPlaybackSpeed);
        }
        if (settings.pitch != 1.0) {
          await _player.setPitch(settings.pitch);
        }
        if (settings.skipSilenceEnabled) {
          await _player.setSkipSilenceEnabled(settings.skipSilenceEnabled);
        }
      }
    } catch (e) {
      debugPrint('Error applying playback settings: $e');
    }

    try {
      await _equalizer.setEnabled(settings.equalizerEnabled);
      await _loudnessEnhancer.setEnabled(settings.loudnessEnhancerEnabled);
      await _loudnessEnhancer.setTargetGain(
        settings.loudnessEnhancerTargetGain,
      );

      final parameters = await _equalizer.parameters;
      for (final entry in settings.equalizerBands.entries) {
        final band = parameters.bands.firstWhere(
          (b) => b.index == entry.key,
          orElse: () => parameters
              .bands[0], // Fallback, though unlikely if index is valid
        );
        if (band.index == entry.key) {
          await band.setGain(
            entry.value.clamp(parameters.minDecibels, parameters.maxDecibels),
          );
        }
      }
    } catch (_) {
      // Equalizer might not be available on this device/platform
    }
  }

  final MusicStreamingService _streamingService = MusicStreamingService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  final YTMusicService _ytMusicService = YTMusicService.instance;

  // SEARCH-only autoplay "Up next" state
  String? _autoUpNextSeededForVideoId;
  bool _autoUpNextInFlight = false;
  int _autoUpNextToken = 0;
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
  bool resolveAllBeforeFeeding = false; // set true to guarantee full metadata
  final Duration _isolateOverallTimeout = const Duration(seconds: 6);
  Stopwatch? _currentLoadStopwatch;
  DateTime? _firstProgressAt;
  DateTime? _firstPlayableAt;
  int _lastProgressResolvedCount = 0;
  DateTime? _loadStartAt;

  // Preparing state exposure via Rx debounce
  bool _internalPreparing = false; // raw intent
  final BehaviorSubject<bool> _preparingSubject = BehaviorSubject<bool>.seeded(
    false,
  );
  StreamSubscription<bool>? _preparingSub;

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
    _playlistWorkerSendPort = await c.future.timeout(
      const Duration(seconds: 5),
    );
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

      // Cleanup old pending requests to prevent leaks
      if (_pendingWorkerRequests.length > 10) {
        final cutoff = localReqId - 20;
        _pendingWorkerRequests.removeWhere((key, _) => key < cutoff);
      }

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
        'quality': SettingsService().preferredQuality,
        'resolverPref': SettingsService().streamingResolverPreference.prefValue,
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

  // Continue listening persistence
  DateTime _lastContinueSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastContinuePositionMs = 0;
  static const Duration _continueSaveThrottle = Duration(seconds: 3);

  // Seeded resume state (loaded from Hive at startup)
  bool _seededFromContinueListening = false;
  Duration? _pendingResumePosition;

  static bool _isHttpUrl(String s) {
    final v = s.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  static bool _isHttpUri(Uri uri) {
    final s = uri.scheme.toLowerCase();
    return s == 'http' || s == 'https';
  }

  static bool _isContentUri(String s) {
    return s.trim().toLowerCase().startsWith('content://');
  }

  static bool _looksLikeFilePath(String urlOrPath) {
    final v = urlOrPath.trim();
    if (v.isEmpty) return false;
    final lower = v.toLowerCase();
    if (lower.startsWith('file://')) return true;
    if (lower.startsWith('content://')) return false;
    if (v.startsWith('/')) return true;
    if (RegExp(r'^[a-zA-Z]:\\').hasMatch(v)) return true;
    return v.contains('\\');
  }

  Map<String, String>? _headersForPlayableUri(Uri uri) {
    // just_audio injects headers via an internal HTTP proxy.
    // That proxy does not support content:// or file:// URIs.
    return _isHttpUri(uri) ? _headers : null;
  }

  bool _shouldUseCacheForPlayableUri(Uri uri) {
    // Only remote streams benefit from proxy/cache.
    return _isHttpUri(uri);
  }

  static int? _tryParseLocalIdFromVideoId(String videoId) {
    if (videoId.startsWith('local_')) {
      return int.tryParse(videoId.substring('local_'.length));
    }
    if (videoId.startsWith('local:')) {
      return int.tryParse(videoId.substring('local:'.length));
    }
    return null;
  }

  static String _androidContentUriForLocalId(int id) {
    return 'content://media/external/audio/media/$id';
  }

  static String _stripFileScheme(String s) {
    final v = s.trim();
    if (v.toLowerCase().startsWith('file://')) {
      return v.substring('file://'.length);
    }
    return v;
  }

  StreamingData _normalizeRestoredTrack(StreamingData t) {
    final raw = (t.streamUrl ?? '').trim();

    // Treat device library IDs as local even if streamUrl is missing.
    final looksLocalId = t.videoId.startsWith('local_');

    // content:// URIs are playable locally even when file paths are inaccessible.
    if (raw.isNotEmpty && _isContentUri(raw)) {
      return t.copyWith(isLocal: true, isAvailable: true);
    }

    // If we have a MediaStore ID, prefer using its content:// URI on Android.
    // This improves resume reliability under scoped storage where file paths may be unreadable.
    if (Platform.isAndroid) {
      final localId = t.localId ?? _tryParseLocalIdFromVideoId(t.videoId);
      if (localId != null && raw.isEmpty) {
        return t.copyWith(
          isLocal: true,
          isAvailable: true,
          streamUrl: _androidContentUriForLocalId(localId),
          localId: t.localId ?? localId,
        );
      }
    }

    // File paths / file:// URIs
    if (raw.isNotEmpty && !_isHttpUrl(raw)) {
      final path = _stripFileScheme(raw);
      bool exists = true;
      try {
        exists = File(path).existsSync();
      } catch (_) {
        exists = true;
      }

      if (!exists && Platform.isAndroid) {
        final localId = t.localId ?? _tryParseLocalIdFromVideoId(t.videoId);
        if (localId != null) {
          return t.copyWith(
            isLocal: true,
            isAvailable: true,
            streamUrl: _androidContentUriForLocalId(localId),
            localId: t.localId ?? localId,
          );
        }
      }

      return t.copyWith(isLocal: true, isAvailable: exists);
    }

    if (looksLocalId) {
      return t.copyWith(isLocal: true);
    }

    // Otherwise, treat as online. Force refetch if the saved URL is stale.
    return t.copyWith(
      isLocal: false,
      streamUrl: null,
      isAvailable: false,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  List<StreamingData> _normalizeRestoredPlaylist(List<StreamingData> tracks) {
    return tracks.map(_normalizeRestoredTrack).toList(growable: false);
  }

  Future<void> _saveContinueListening({required Duration position}) async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) return;

    // Throttle writes (and avoid writing the same position repeatedly)
    final now = DateTime.now();
    if (now.difference(_lastContinueSaveAt) < _continueSaveThrottle) return;
    final posMs = position.inMilliseconds;
    if ((posMs - _lastContinuePositionMs).abs() < 800) return;
    _lastContinueSaveAt = now;
    _lastContinuePositionMs = posMs;

    // Keep the session lightweight
    final capped =
        _playlist.length > 200 ? _playlist.take(200).toList() : _playlist;

    // Apply overrides before persisting so the resume UI matches the user's edits.
    final applied = capped
        .map((t) => MetadataOverridesStore.maybeApplySync(t))
        .toList(growable: false);

    await ContinueListeningStore.save(
      ContinueListeningSession(
        playlist: applied,
        currentIndex: _currentIndex.clamp(0, applied.length - 1),
        position: position,
        sourceType: _sourceType,
        sourceName: _sourceName,
        updatedAt: now,
      ),
    );
  }

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

  // Track the player's raw audio index so we can detect track changes even when
  // our mapping is temporarily incomplete.
  int? _lastAudioChildIndex;

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
  AndroidLoudnessEnhancer get loudnessEnhancer => _loudnessEnhancer;
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

  /// RxDart-composed TrackInfo stream combining underlying player streams.
  /// Backed by a BehaviorSubject for broadcast + replay to support multiple listeners safely.
  final BehaviorSubject<TrackInfo> _trackInfoSubject =
      BehaviorSubject<TrackInfo>();
  Stream<TrackInfo> get trackInfo$ => _trackInfoSubject.stream;
  StreamSubscription<TrackInfo>? _trackInfoRxSub;

  void _startTrackInfoRx() {
    _trackInfoRxSub?.cancel();
    final rx$ = Rx.combineLatest6<Duration, Duration?, PlayerState, int?, bool,
        LoopMode, TrackInfo>(
      _player.positionStream,
      _player.durationStream,
      _player.playerStateStream,
      _player.currentIndexStream,
      _player.shuffleModeEnabledStream,
      _player.loopModeStream,
      (pos, dur, ps, idx, shuf, loop) {
        final track = currentTrack;
        final total = _playlist.length;
        final progress = (dur != null && dur.inMilliseconds > 0)
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final lm = _loopModeString[loop] ?? 'off';
        return TrackInfo(
          track: track,
          currentIndex: _currentIndex,
          totalTracks: total,
          isPlaying: ps.playing,
          isShuffleEnabled: shuf,
          loopMode: lm,
          position: pos,
          duration: dur,
          progress: progress,
          sourceName: _sourceName,
          sourceType: _sourceType,
        );
      },
    ).distinct((a, b) => a == b).sampleTime(const Duration(milliseconds: 250));

    _trackInfoRxSub = rx$.listen(
      (t) => _trackInfoSubject.add(t),
      onError: _trackInfoSubject.addError,
    );
  }

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
      otherChanged = (info.track?.videoId != prev.track?.videoId) ||
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

    // Note: We intentionally avoid calling setAndroidAudioAttributes.
    // Audio focus and attributes are handled via audio_session configuration above.

    // Emit initial current track
    _currentTrackController.add(currentTrack);
    _emitTrackInfo(force: true);

    // Start Rx-backed track info and seed an initial value
    _startTrackInfoRx();
    _trackInfoSubject.add(_computeTrackInfo());

    // Debounced preparing state
    _preparingSub = _preparingSubject
        .debounceTime(const Duration(milliseconds: 120))
        .distinct()
        .listen((v) => isPreparing.value = v);

    // Listen to player events
    _player.currentIndexStream.listen((audioIndex) {
      if (audioIndex != null) {
        // Avoid duplicate handling for the same emitted value.
        if (_lastAudioChildIndex == audioIndex) return;
        _lastAudioChildIndex = audioIndex;

        // audioIndex is the index in the ConcatenatingAudioSource (child index).
        // It is NOT the sequence index (playback order), so we don't need to map through shuffle indices.
        // We simply map the child index to our internal playlist index.
        int newIndex = _currentIndex;
        if (audioIndex >= 0 && audioIndex < _childToPlaylistIndex.length) {
          newIndex = _childToPlaylistIndex[audioIndex];
        } else if (audioIndex >= 0 && audioIndex < _playlist.length) {
          // Fallback for contiguous queues when mapping hasn't been updated yet.
          newIndex = audioIndex;
        }

        if (newIndex != _currentIndex) {
          _currentIndex = newIndex;
          _currentTrackController.add(currentTrack);
          _emitTrackInfo(force: true);
          notifyListeners();
          _preloadUpcomingSongs();
          _warmNextConnection();
          _applyEqualizerSettings();

          // Incrementally extend the in-memory queue to keep transitions smooth
          // without rebuilding the entire audio source mid-playback.
          _enqueueInsertion(() => _appendContiguousReadyTail(maxToAppend: 2));

          // For SEARCH playback, start fetching "Up next" early for the new track
          // so the queue continues seamlessly after this song.
          _maybeSeedUpNextEarly(reason: 'track-change');
        }
      }
    });

    // Keep metadata in sync with what the player is actually playing by
    // reading the current MediaItem tag from the sequence state.
    _player.sequenceStateStream.listen((seqState) {
      final currentSource = seqState?.currentSource;
      final tag = currentSource?.tag;
      if (tag is! MediaItem) return;

      final String videoId =
          (tag.extras is Map && (tag.extras as Map).containsKey('videoId'))
              ? ((tag.extras as Map)['videoId'] as String? ?? tag.id)
              : tag.id;

      int newIndex = _playlist.indexWhere((t) => t.videoId == videoId);
      if (newIndex < 0) {
        final audioIndex = seqState?.currentIndex;
        if (audioIndex != null &&
            audioIndex >= 0 &&
            audioIndex < _childToPlaylistIndex.length) {
          newIndex = _childToPlaylistIndex[audioIndex];
        }
      }
      if (newIndex < 0 || newIndex >= _playlist.length) return;

      if (newIndex != _currentIndex) {
        _currentIndex = newIndex;
        _currentTrackController.add(currentTrack);
        _emitTrackInfo(force: true);
        notifyListeners();
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
    _player.positionStream.listen((pos) {
      _emitTrackInfo();
      // Best-effort persistence for resume
      _saveContinueListening(position: pos);
    });
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
          final applied = MetadataOverridesStore.maybeApplySync(t);
          LibraryStore.addRecent(applied);
          LibraryStore.incrementPlayCount(applied);
          _lastRecentVideoId = t.videoId;
        }

        // When playback starts/resumes on a SEARCH track, fetch up-next early
        // while the song is playing, and append to the current queue.
        _maybeSeedUpNextEarly(reason: 'play-start');
      }
    });

    // Seed last played song + playlist for UI continuity after app restart.
    // We avoid eagerly rebuilding the audio source here to keep startup fast;
    // the first user-initiated play will prepare and seek to the saved position.
    _seedFromContinueListeningIfNeeded();
  }

  bool _shouldAutoUpNext() {
    if (_sourceType != 'SEARCH') return false;
    if (_player.shuffleModeEnabled) return false;
    final t = currentTrack;
    if (t == null) return false;
    if (t.isLocal) return false;
    // Avoid growing queues in offline mode (no network permitted).
    if (SettingsService().offlineMode) return false;
    return true;
  }

  void _maybeSeedUpNextEarly({required String reason}) {
    // Fire-and-forget so we never block playback/UI.
    () async {
      if (!_shouldAutoUpNext()) return;

      final t = currentTrack;
      if (t == null) return;

      // Only fetch when we're at/near the tail to avoid excessive requests.
      // With the new "single track" search playback, this triggers immediately.
      final remaining = (_playlist.length - 1) - _currentIndex;
      if (remaining > 1) return;

      if (_autoUpNextSeededForVideoId == t.videoId) return;
      if (_autoUpNextInFlight) return;

      _autoUpNextInFlight = true;
      _autoUpNextSeededForVideoId = t.videoId;
      final localToken = ++_autoUpNextToken;

      try {
        final upNext = await _ytMusicService.getUpNextQueue(
          t.videoId,
          timeout: const Duration(seconds: 15),
        );
        // Superseded or no longer in SEARCH context
        if (localToken != _autoUpNextToken) return;
        if (_sourceType != 'SEARCH') return;
        if (upNext.isEmpty) return;

        // Deduplicate against current queue
        final existingIds = _playlist.map((e) => e.videoId).toSet();
        final toAppend = <StreamingData>[];
        for (final u in upNext) {
          final id = u.videoId;
          if (id.isEmpty) continue;
          if (!RegExp(r'^[a-zA-Z0-9-_]{11}$').hasMatch(id)) continue;
          if (existingIds.contains(id)) continue;
          existingIds.add(id);
          toAppend.add(u);
          // Keep each fetch bounded to avoid huge queue spikes.
          if (toAppend.length >= 20) break;
        }
        if (toAppend.isEmpty) return;

        // Ensure growable playlist even when restored from fixed-length sources.
        _playlist = List<StreamingData>.from(_playlist)..addAll(toAppend);
        notifyListeners();
        unawaited(LibraryStore.saveQueue(_playlist));

        // Resolve a few upcoming streams early and append them to the audio source
        // without a full rebuild to avoid stutters.
        final idsToResolve =
            toAppend.take(4).map((e) => e.videoId).toList(growable: false);
        if (idsToResolve.isNotEmpty) {
          await _batchProcessTracksForAutoplay(idsToResolve);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Up-next seed failed ($reason): $e');
        }
      } finally {
        if (localToken == _autoUpNextToken) {
          _autoUpNextInFlight = false;
        }
      }
    }();
  }

  /// Resolve stream URLs for a small set of videoIds and then append any newly
  /// ready contiguous tail items to the active ConcatenatingAudioSource.
  Future<void> _batchProcessTracksForAutoplay(List<String> videoIds) async {
    if (videoIds.isEmpty) return;
    try {
      final result = await _streamingService.batchGetStreamingUrls(
        videoIds,
        quality: _getPreferredQuality(),
      );

      bool anyBecameReady = false;
      for (final streamingData in result.successful) {
        final index = _playlist.indexWhere(
          (track) => track.videoId == streamingData.videoId,
        );
        if (index == -1) continue;

        final wasReady = _playlist[index].isReady;
        final old = _playlist[index];
        final merged = old.copyWith(
          title: old.title.isNotEmpty ? old.title : streamingData.title,
          artist: old.artist.isNotEmpty ? old.artist : streamingData.artist,
          thumbnailUrl: streamingData.thumbnailUrl ?? old.thumbnailUrl,
          duration: old.duration ?? streamingData.duration,
          streamUrl: streamingData.streamUrl,
          quality: streamingData.quality,
          cachedAt: streamingData.cachedAt,
          isAvailable: streamingData.isAvailable,
        );
        _playlist[index] = merged;
        if (!wasReady && merged.isReady) {
          anyBecameReady = true;
        }
      }

      if (anyBecameReady) {
        _enqueueInsertion(() => _appendContiguousReadyTail(maxToAppend: 4));
        _warmNextConnection();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Autoplay URL prefetch failed: $e');
      }
    }
  }

  void _seedFromContinueListeningIfNeeded() {
    if (_seededFromContinueListening) return;
    if (_playlist.isNotEmpty) return;

    final session = ContinueListeningStore.loadSync();
    if (session == null) return;
    if (session.playlist.isEmpty) return;

    _seededFromContinueListening = true;
    final normalized = _normalizeRestoredPlaylist(session.playlist);
    _playlist = normalized
        .map((t) => MetadataOverridesStore.maybeApplySync(t))
        .toList(growable: false);
    _currentIndex = session.currentIndex.clamp(0, _playlist.length - 1);
    _sourceType = session.sourceType ?? 'CONTINUE';
    _sourceName = session.sourceName ?? 'Continue listening';
    _pendingResumePosition = session.position;

    _playlistFingerprint = _computeFingerprint(_playlist);
    _materializedIndices.clear();
    _preloadedIndices.clear();
    _childToPlaylistIndex = <int>[];
    _lastAudioChildIndex = null;

    _currentTrackController.add(currentTrack);
    _emitTrackInfo(force: true);
    notifyListeners();
  }

  Future<bool> restoreLastSession({bool autoPlay = true}) async {
    await ContinueListeningStore.ensureReady();
    final session = ContinueListeningStore.loadSync();
    if (session == null) return false;
    if (session.playlist.isEmpty) return false;

    final playlist = _normalizeRestoredPlaylist(session.playlist)
        .map((t) => MetadataOverridesStore.maybeApplySync(t))
        .toList(growable: false);

    await loadPlaylist(
      playlist,
      initialIndex: session.currentIndex,
      autoPlay: false,
      sourceType: session.sourceType ?? 'CONTINUE',
      sourceName: session.sourceName ?? 'Continue listening',
      withTransition: true,
    );

    try {
      await seek(session.position, index: session.currentIndex);
    } catch (_) {}

    if (autoPlay) {
      try {
        await play();
      } catch (_) {}
    }
    return true;
  }

  /// Re-apply dynamic settings that can change at runtime (speed, volume)
  Future<void> refreshDynamicSettings() async {
    final settings = SettingsService();
    if (!settings.isReady) return;

    bool isLocal = false;
    if (_playlist.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _playlist.length) {
      isLocal = _playlist[_currentIndex].isLocal;
    }

    try {
      if (isLocal) {
        if (_player.speed != 1.0) await _player.setSpeed(1.0);
      } else {
        await _player.setSpeed(settings.defaultPlaybackSpeed);
      }
    } catch (_) {}
    try {
      await _player.setVolume(settings.defaultVolume);
    } catch (_) {}
  }

  /// Backwards compatible API: always forces full replace semantics.
  Future<void> loadPlaylist(
    List<StreamingData> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    String? sourceName,
    String sourceType = 'QUEUE',
    bool withTransition = false,
  }) async {
    await replacePlaylist(
      tracks,
      initialIndex: initialIndex,
      autoPlay: autoPlay,
      sourceName: sourceName,
      sourceType: sourceType,
      withTransition: withTransition,
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
    bool withTransition = false,
    bool force = false,
  }) async {
    // Any explicit load replaces pending resume state.
    _pendingResumePosition = null;
    _seededFromContinueListening = false;

    // Enforce global max queue size of 25, keeping the selected track inside the window
    List<StreamingData> cappedTracks = newTracks;
    int cappedInitialIndex = initialIndex.clamp(0, newTracks.length - 1);

    /* Removed capping logic as per user request
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
    */

    final newFp = _computeFingerprint(cappedTracks);
    final same =
        !force && _playlistFingerprint != null && _playlistFingerprint == newFp;
    if (same) {
      if (cappedInitialIndex >= 0 && cappedInitialIndex < _playlist.length) {
        await jumpToIndex(cappedInitialIndex);
      }
      return false;
    }

    // OPTIMIZATION: Start fetching the first track immediately, before stopping the player.
    // This parallelizes the network request with the player teardown.
    Future<StreamingData?>? firstTrackFuture;
    if (cappedInitialIndex >= 0 && cappedInitialIndex < cappedTracks.length) {
      final t = cappedTracks[cappedInitialIndex];
      if (!t.isLocal && (!t.isReady || t.streamUrl == null)) {
        firstTrackFuture = _streamingService.fetchStreamingData(
          t.videoId,
          _getPreferredQuality(),
          preference: SettingsService().streamingResolverPreference,
        );
      }
    }

    // If we are actually replacing with a different queue and caller requests
    // a smooth transition, pause+stop first so old audio stops immediately.
    // (Some devices/backends behave better when paused before stop.)
    if (withTransition) {
      try {
        await _player.pause();
      } catch (_) {}
      try {
        await _player.stop();
      } catch (_) {}
    }
    _playlistFingerprint = newFp;

    final int requestId = ++_loadRequestId;
    _setPreparing(true);
    try {
      // Capture old images before replacing to clear unused ones later
      final oldImages = _playlist
          .map((t) => t.thumbnailUrl)
          .where((url) => url != null)
          .cast<String>()
          .toSet();

      _playlist = cappedTracks;
      _currentIndex = cappedInitialIndex;
      _applyEqualizerSettings();
      _materializedIndices.clear();
      _preloadedIndices.clear();

      // Calculate unused images and remove them from cache to save memory
      final newImages = _playlist
          .map((t) => t.thumbnailUrl)
          .where((url) => url != null)
          .cast<String>()
          .toSet();

      final unused = oldImages.difference(newImages);
      if (unused.isNotEmpty) {
        // Run in background to avoid blocking playback start
        Future.microtask(() => _imageCacheService.removeSpecificImages(unused));
      }

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

      // NEW: Offline Mode Pipeline
      // If explicitly playing downloads or offline mode is enabled, use the dedicated offline pipeline.
      // This bypasses network resolution, caching, and complex isolate logic.
      final settings = SettingsService();
      if (sourceType == 'DOWNLOADS' ||
          sourceType == 'OFFLINE' ||
          settings.offlineMode) {
        await _loadOfflinePlaylist(requestId: requestId, autoPlay: autoPlay);
        return true;
      }

      final quality = _getPreferredQuality();
      if (resolveAllBeforeFeeding) {
        await _resolveAllTracksThenBuild(
          requestId: requestId,
          autoPlay: autoPlay,
        );
      } else {
        // Prioritize current track and a few neighbors for faster first play
        final critical = <int>{_currentIndex};
        if (_currentIndex - 1 >= 0) critical.add(_currentIndex - 1);
        if (_currentIndex + 1 < _playlist.length) {
          critical.add(_currentIndex + 1);
        }
        if (_currentIndex + 2 < _playlist.length) {
          critical.add(_currentIndex + 2);
        }

        Future<void> resolveIndex(int idx) async {
          final existing = _playlist[idx];
          if (existing.isLocal && existing.streamUrl != null) {
            // Never resolve local tracks via network.
            if (!existing.isReady) {
              _playlist[idx] = existing.copyWith(isAvailable: true);
            }
            return;
          }
          if (existing.isReady && existing.streamUrl != null) {
            return;
          }
          final r = await _streamingService.fetchStreamingData(
            existing.videoId,
            quality,
            preference: SettingsService().streamingResolverPreference,
          );
          if (r != null) {
            _playlist[idx] = existing.copyWith(
              streamUrl: r.streamUrl,
              quality: r.quality,
              cachedAt: r.cachedAt,
              isAvailable: true,
              title: existing.title.isNotEmpty ? existing.title : r.title,
              artist: existing.artist.isNotEmpty ? existing.artist : r.artist,
              duration: existing.duration ?? r.duration,
              thumbnailUrl: r.thumbnailUrl ?? existing.thumbnailUrl,
            );
          }
        }

        // 1. Resolve CURRENT track immediately and play
        if (firstTrackFuture != null) {
          StreamingData? r;
          try {
            r = await firstTrackFuture;
          } catch (_) {
            // Ignore error from prefetch, fallback to standard resolve
          }

          if (r != null && _currentIndex < _playlist.length) {
            final old = _playlist[_currentIndex];
            _playlist[_currentIndex] = old.copyWith(
              streamUrl: r.streamUrl,
              quality: r.quality,
              cachedAt: r.cachedAt,
              isAvailable: true,
              title: old.title.isNotEmpty ? old.title : r.title,
              artist: old.artist.isNotEmpty ? old.artist : r.artist,
              duration: old.duration ?? r.duration,
              thumbnailUrl: r.thumbnailUrl ?? old.thumbnailUrl,
            );
          } else {
            // Fallback if prefetch failed or returned null
            await resolveIndex(_currentIndex);
          }
        } else {
          await resolveIndex(_currentIndex);
        }

        if (requestId != _loadRequestId) return false;

        // Minimal single-source build for the first track if ready
        if (_playlist[_currentIndex].isReady &&
            _playlist[_currentIndex].streamUrl != null) {
          await _setMinimalSingleSource(_currentIndex, autoPlay: autoPlay);
          _firstPlayableAt ??= DateTime.now();
          if (autoPlay) _setPreparing(false);

          // For large playlists, start progressive isolate build to assemble full source in background
          final largeAndProgressive =
              _playlist.length >= _isolateThreshold && enableProgressiveIsolate;
          if (largeAndProgressive) {
            // ignore: discarded_futures
            _startProgressiveIsolateBuild(
              requestId: requestId,
              autoPlay: autoPlay,
              initialFastMode: true,
            );
          }
        }

        // 2. Resolve neighbors (previous/next) in background
        final neighbors = critical.where((i) => i != _currentIndex).toList();
        for (final idx in neighbors) {
          if (requestId != _loadRequestId) return false;
          await resolveIndex(idx);
        }

        // After resolving neighbors, try to extend the current audio queue
        // (cheap append) rather than rebuilding sources.
        if (requestId != _loadRequestId) return false;
        _enqueueInsertion(() => _appendContiguousReadyTail(maxToAppend: 2));

        // Fire-and-forget background resolution of remaining tracks
        final remaining = <int>[];
        for (int i = 0; i < _playlist.length; i++) {
          if (critical.contains(i)) continue;
          if (!_playlist[i].isReady || _playlist[i].streamUrl == null) {
            remaining.add(i);
          }
        }
        if (remaining.isNotEmpty) {
          () async {
            final futures = <Future<void>>[];
            for (final idx in remaining) {
              futures.add(resolveIndex(idx));
            }
            try {
              await Future.wait(futures, eagerError: false);
            } catch (_) {}
            if (requestId != _loadRequestId) return;
            // Avoid rebuilding the full source here; append a small tail if ready.
            _enqueueInsertion(() => _appendContiguousReadyTail(maxToAppend: 4));
            _warmNextConnection();
          }();
        } else {
          // If no remaining tracks to resolve, ensure we still rebuild the audio source
          // to include the full playlist (unless using progressive isolate which handles it separately).
          final largeAndProgressive =
              _playlist.length >= _isolateThreshold && enableProgressiveIsolate;

          if (!largeAndProgressive) {
            () async {
              if (requestId != _loadRequestId) return;
              _enqueueInsertion(
                  () => _appendContiguousReadyTail(maxToAppend: 4));
              _warmNextConnection();
            }();
          }
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
          final loadedCount =
              _playlist.where((t) => t.isReady && t.streamUrl != null).length;
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
            'progressive': _playlist.length >= _isolateThreshold &&
                enableProgressiveIsolate,
            'fingerprint': _playlistFingerprint,
            'largeFastPath': _playlist.length >= _isolateThreshold &&
                enableProgressiveIsolate,
          },
        );
      }
    }
  }

  /// Add a single track to the current playlist
  Future<void> addTrack(StreamingData track) async {
    _playlist.add(track);

    // Prune history if playlist gets too long and we are far ahead
    // This prevents memory growth during long sessions
    bool pruned = false;
    /* Removed pruning logic as per user request
    if (_playlist.length > 50 && _currentIndex > 20) {
      // Remove the first item (oldest history)
      // removeTrack handles _rebuildAudioSource and notifyListeners
      await removeTrack(0);
      pruned = true;
    }
    */

    // Rebuild audio source to keep order consistent when a track becomes ready
    if (!pruned && track.isReady) {
      await _rebuildAudioSource();
    }

    if (!pruned) notifyListeners();
    if (!pruned) {
      unawaited(LibraryStore.saveQueue(_playlist));
    }
  }

  /// Dedicated pipeline for offline playback.
  /// Directly loads local files into ConcatenatingAudioSource without network checks.
  Future<void> _loadOfflinePlaylist({
    required int requestId,
    required bool autoPlay,
  }) async {
    final children = <AudioSource>[];
    final readyIndices = <int>[];

    for (int i = 0; i < _playlist.length; i++) {
      final t = _playlist[i];
      // For offline playback, we expect a valid local path in streamUrl
      if (t.streamUrl == null) continue;

      // Mark as ready/available since it's local
      if (!t.isReady) {
        _playlist[i] = t.copyWith(isAvailable: true, isLocal: true);
      }

      children.add(
        AudioSource.uri(
          _toPlayableUri(t.streamUrl!, isLocal: true),
          tag: MediaItem(
            id: t.videoId,
            title: t.title,
            artist: t.artist,
            duration: t.duration,
            artUri:
                t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
            extras: {'videoId': t.videoId, 'isLocal': true},
          ),
        ),
      );
      readyIndices.add(i);
    }

    if (children.isEmpty) {
      _setPreparing(false);
      return;
    }

    _childToPlaylistIndex = List<int>.from(readyIndices);
    final initChildIndex = _getAudioSourceIndex(
      _currentIndex,
    ).clamp(0, children.length - 1);

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: children,
          useLazyPreparation: true,
          shuffleOrder: DefaultShuffleOrder(),
        ),
        initialIndex: initChildIndex,
        initialPosition: Duration.zero,
      );

      if (autoPlay) await _player.play();

      _currentTrackController.add(_playlist[_currentIndex]);
      _emitTrackInfo(force: true);
    } catch (e) {
      debugPrint('Error loading offline playlist: $e');
    } finally {
      if (requestId == _loadRequestId) {
        _setPreparing(false);
      }
    }
  }

  // Resolve all tracks' stream URLs and metadata before building audio source
  Future<void> _resolveAllTracksThenBuild({
    required int requestId,
    required bool autoPlay,
  }) async {
    final quality = _getPreferredQuality();
    final settings = SettingsService();
    // Resolve in parallel with existing service limits
    final futures = <Future<void>>[];
    for (int i = 0; i < _playlist.length; i++) {
      if (_playlist[i].isReady && _playlist[i].streamUrl != null) continue;

      // Local tracks should never be resolved via network.
      if (_playlist[i].isLocal) {
        final t = _playlist[i];
        if (t.streamUrl != null && !t.isAvailable) {
          _playlist[i] = t.copyWith(isAvailable: true);
        }
        continue;
      }

      // Skip network fetch if offline mode is enabled
      if (settings.offlineMode && !_playlist[i].isLocal) continue;

      final idx = i;
      futures.add(() async {
        final r = await _streamingService.fetchStreamingData(
          _playlist[idx].videoId,
          quality,
          preference: SettingsService().streamingResolverPreference,
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

      final raw = t.streamUrl!;
      final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
      final headers = _headersForPlayableUri(uri);
      children.add(
        AudioSource.uri(
          uri,
          headers: headers,
          tag: MediaItem(
            id: t.videoId,
            title: t.title,
            artist: t.artist,
            duration: t.duration,
            artUri:
                t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
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
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: children,
          useLazyPreparation: true,
          shuffleOrder: DefaultShuffleOrder(),
        ),
        initialIndex: initChildIndex,
        initialPosition: Duration.zero,
      );
    } on UnimplementedError catch (e, st) {
      if (kDebugMode) {
        debugPrint('setAudioSource unsupported on current backend: $e\n$st');
      }
      // Auto fallback: switch backend to system & notify user via debug log.
    }
    if (wasShuffled) await _player.setShuffleModeEnabled(true);
    if (autoPlay) await _player.play();

    // Immediate warm-up for current and next track now that primary is set
    _warmNextConnection();
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
    unawaited(LibraryStore.saveQueue(_playlist));
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
      unawaited(LibraryStore.saveQueue(_playlist));
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
      unawaited(LibraryStore.saveQueue(_playlist));
    }
  }

  /// Play current track
  Future<void> play() async {
    final pending = _pendingResumePosition;
    if (pending != null) {
      // Clear first to avoid loops if seek triggers state updates.
      _pendingResumePosition = null;
      try {
        await seek(pending, index: _currentIndex);
      } catch (_) {
        // Best-effort; still attempt to play.
      }
    }
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

  /// Seek to position. Returns true if successful.
  Future<bool> seek(Duration position, {int? index}) async {
    if (index != null) {
      if (index < 0 || index >= _playlist.length) return false;

      // Ensure streaming/local info ready if needed
      await _ensureTrackReady(index);
      if (!_playlist[index].isReady) {
        // Local tracks should never trigger network refresh during resume.
        if (_playlist[index].isLocal) {
          // Best-effort: attempt to re-mark availability / content:// fallback.
          final fixed = _normalizeRestoredTrack(_playlist[index]);
          _playlist[index] = fixed;
        } else {
          // Try one more time with force refresh if it failed
          await _streamingService.refreshStreamingData(
            _playlist[index].videoId,
            _getPreferredQuality(),
          );
          // Re-check
          await _ensureTrackReady(index);
        }
        if (!_playlist[index].isReady) return false;
      }

      // If mapping doesn't include the target yet, rebuild preserving position
      if (!_childToPlaylistIndex.contains(index)) {
        await _rebuildAudioSource(
          preferPlaylistIndex: _currentIndex,
          preservePosition: true,
        );
      }
      final childIndex = _childToPlaylistIndex.indexOf(index);
      if (childIndex < 0) return false; // still not mapped

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
      return true;
    }
    // Seek within current track only
    await _player.seek(position);
    return true;
  }

  /// Skip to next track
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;

    int nextIndex;
    if (_isShuffleEnabled && _childToPlaylistIndex.isNotEmpty) {
      final seqLen = _childToPlaylistIndex.length;
      final currentSeq = _player.currentIndex ??
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

    // If target wasnâ€™t ready and nothing changed, try advancing to next ready child.
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
      final currentSeq = _player.currentIndex ??
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
      final currentSeq = _player.currentIndex ??
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
      if (shuffle != null) {
        if (sequenceIndex >= shuffle.length) {
          return _currentIndex;
        }
        childIndex = shuffle[sequenceIndex];
      }
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
    if (shuffle == null) return childIndex;
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
    notifyListeners();
    try {
      await _player.setShuffleModeEnabled(enabled);
    } catch (e) {
      _isShuffleEnabled = !enabled;
      notifyListeners();
      debugPrint('Error setting shuffle mode: $e');
    }
  }

  /// Set loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    final oldMode = _loopMode;
    _loopMode = mode;
    notifyListeners();
    try {
      await _player.setLoopMode(mode);
    } catch (e) {
      _loopMode = oldMode;
      notifyListeners();
      debugPrint('Error setting loop mode: $e');
    }
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

    // Local tracks: ensure availability + ensure present in audio source, but never hit network.
    if (_playlist[index].isLocal) {
      final t = _playlist[index];

      StreamingData fixed = t;
      final raw = (t.streamUrl ?? '').trim();
      if (raw.isNotEmpty && _isContentUri(raw)) {
        if (!t.isAvailable) {
          fixed = t.copyWith(isAvailable: true, isLocal: true);
        }
      } else if (raw.isEmpty && Platform.isAndroid) {
        final localId = t.localId ?? _tryParseLocalIdFromVideoId(t.videoId);
        if (localId != null) {
          fixed = t.copyWith(
            isAvailable: true,
            isLocal: true,
            streamUrl: _androidContentUriForLocalId(localId),
            localId: t.localId ?? localId,
          );
        }
      } else if (raw.isNotEmpty && !_isHttpUrl(raw)) {
        final path = _stripFileScheme(raw);
        bool exists = true;
        try {
          exists = File(path).existsSync();
        } catch (_) {
          exists = true;
        }
        if (!exists && Platform.isAndroid) {
          final localId = t.localId ?? _tryParseLocalIdFromVideoId(t.videoId);
          if (localId != null) {
            fixed = t.copyWith(
              isAvailable: true,
              isLocal: true,
              streamUrl: _androidContentUriForLocalId(localId),
              localId: t.localId ?? localId,
            );
          } else {
            fixed = t.copyWith(isAvailable: exists, isLocal: true);
          }
        } else {
          fixed = t.copyWith(isAvailable: exists, isLocal: true);
        }
      }

      if (!identical(fixed, t)) {
        _playlist[index] = fixed;
      }

      if (_playlist[index].isReady && !_childToPlaylistIndex.contains(index)) {
        await _rebuildAudioSource(
          preferPlaylistIndex: _currentIndex,
          preservePosition: true,
          requestId: requestId,
        );
      }
      return;
    }

    final track = _playlist[index];
    if (!track.isReady) {
      final result = await _streamingService.fetchStreamingData(
        track.videoId,
        _getPreferredQuality(),
        preference: SettingsService().streamingResolverPreference,
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
          .where((t) => !t.isLocal && (!t.isReady || t.streamUrl == null))
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
      final videoIds =
          newIndicesToPreload.map((index) => _playlist[index].videoId).toList();

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
    // Skip rebuilds for offline mode to prevent stuttering/stopping
    if (_sourceType == 'DOWNLOADS' || SettingsService().offlineMode) return;

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
            final raw = t.streamUrl!;
            final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
            final headers = _headersForPlayableUri(uri);
            final tag = MediaItem(
              id: t.videoId,
              title: t.title,
              artist: t.artist,
              duration: t.duration,
              artUri:
                  t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
              extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
            );

            // Use LockCachingAudioSource for remote streams if not using MediaKit
            // MediaKit backend might not support the proxy URL, so we skip cache for it.
            final useCache = _shouldUseCacheForPlayableUri(uri);

            if (useCache) {
              children.add(
                LockCachingAudioSource(
                  uri,
                  tag: tag,
                  headers: headers,
                  // cacheKey: t.videoId, // Not supported in this version of just_audio_cache?
                ),
              );
            } else {
              children.add(AudioSource.uri(uri, tag: tag, headers: headers));
            }
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
          final raw = t.streamUrl!;
          final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
          final headers = _headersForPlayableUri(uri);
          final tag = MediaItem(
            id: t.videoId,
            title: t.title,
            artist: t.artist,
            duration: t.duration,
            artUri:
                t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
            extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
          );

          final useCache = _shouldUseCacheForPlayableUri(uri);

          if (useCache) {
            children.add(
              LockCachingAudioSource(
                uri,
                tag: tag,
                headers: headers,
                // cacheKey: t.videoId,
              ),
            );
          } else {
            children.add(AudioSource.uri(uri, tag: tag, headers: headers));
          }
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

    // Optimization: If we are currently playing the correct track in a ConcatenatingAudioSource,
    // and we just want to append/insert new tracks, try to do it in-place to avoid interruption.
    // This is complex because we need to match existing children.
    // For now, we rely on setAudioSources but we check if we can skip it if nothing changed.
    // (Logic omitted for brevity, relying on setAudioSources for correctness)

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
      fallbackPlaylistIndex ??=
          readyIndices.isNotEmpty ? readyIndices.first : 0;
      newChildIndex = _getAudioSourceIndex(fallbackPlaylistIndex);
    }

    // Create and set the new audio source
    // Decide initial position: keep position only if staying on same playlist index and that track is ready
    final keepPosition = preservePosition &&
        desiredPlaylistIndex == _currentIndex &&
        _playlist[desiredPlaylistIndex].isReady;

    // Before applying, ensure this call hasn't been superseded
    if (requestId != null && requestId != _loadRequestId) return;

    // If we are just updating the list but the current track is the same,
    // we might be interrupting playback.
    // Check if we can avoid setting source if it's effectively the same for the current item.
    // However, just_audio doesn't support seamless replacement of the whole list easily without gap.
    // The best we can do is ensure we don't rebuild unnecessarily.

    // To guarantee initial index selects the intended child regardless of shuffle,
    // temporarily disable shuffle, set source with child index, then restore shuffle mode.
    final bool wasShuffled = _player.shuffleModeEnabled;
    if (wasShuffled) {
      await _player.setShuffleModeEnabled(false);
    }

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: children,
          useLazyPreparation: true,
          shuffleOrder: DefaultShuffleOrder(),
        ),
        initialIndex: newChildIndex.clamp(0, children.length - 1),
        initialPosition: keepPosition ? prevPosition : Duration.zero,
      );
    } on UnimplementedError catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'setAudioSources unsupported on current backend (rebuild): $e\n$st',
        );
      }
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
      // Only attempt network refresh for HTTP(S) streams.
      final failingRaw = _playlist[failingPlaylistIndex].streamUrl;
      if (failingRaw == null) rethrow;
      final failingUri =
          _toPlayableUri(failingRaw, isLocal: _looksLikeFilePath(failingRaw));
      if (!_isHttpUri(failingUri)) rethrow;

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
            final raw = t.streamUrl!;
            final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
            final headers = _headersForPlayableUri(uri);
            retryChildren.add(
              AudioSource.uri(
                uri,
                headers: headers,
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
          await _player.setAudioSource(
            ConcatenatingAudioSource(
              children: retryChildren,
              useLazyPreparation: true,
              shuffleOrder: DefaultShuffleOrder(),
            ),
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
    final v = urlOrPath.trim();

    // Android MediaStore URIs for scoped storage playback.
    if (v.startsWith('content://')) {
      return Uri.parse(v);
    }

    if (v.startsWith('file://')) {
      return Uri.parse(v);
    }

    if (isLocal) {
      // Treat as a file path.
      final file = File(v);
      return Uri.file(file.path);
    }

    // If it looks like a file path, prefer file URI.
    if (v.startsWith('/') || v.contains('\\')) {
      return Uri.file(v);
    }

    return Uri.parse(v);
  }

  /// Dispose resources
  @override
  void dispose() {
    _trackInfoRxSub?.cancel();
    _trackInfoSubject.close();
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
    _preparingSub?.cancel();
    _preparingSubject.close();
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
    final raw = t.streamUrl!;
    final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
    final headers = _headersForPlayableUri(uri);
    _setMinimalChildMapping(playlistIndex);
    try {
      // Use setAudioSource to create a ConcatenatingAudioSource with 1 item
      // This allows future updates to potentially append to it seamlessly.
      final tag = MediaItem(
        id: t.videoId,
        title: t.title,
        artist: t.artist,
        duration: t.duration,
        artUri: t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
        extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
      );

      final useCache = _shouldUseCacheForPlayableUri(uri);

      AudioSource source;
      if (useCache) {
        source = LockCachingAudioSource(
          uri,
          tag: tag,
          headers: headers,
          // cacheKey: t.videoId,
        );
      } else {
        source = AudioSource.uri(uri, tag: tag, headers: headers);
      }

      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: [source],
          useLazyPreparation: true,
          shuffleOrder: DefaultShuffleOrder(),
        ),
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
    } on UnimplementedError catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'setAudioSource unsupported on current backend (minimal single): $e\n$st',
        );
      }
    }
    if (autoPlay) {
      await _player.play();
    }

    // Resolve & append the next track(s) in the background for seamless advance.
    // This avoids full rebuilds that can cause stutters/repeats.
    final int requestId = _loadRequestId;
    () async {
      final next = playlistIndex + 1;
      if (next >= _playlist.length) return;
      try {
        final existing = _playlist[next];
        if (!existing.isLocal &&
            (!existing.isReady || existing.streamUrl == null)) {
          final r = await _streamingService.fetchStreamingData(
            existing.videoId,
            _getPreferredQuality(),
            preference: SettingsService().streamingResolverPreference,
          );
          if (r != null && next < _playlist.length) {
            _playlist[next] = existing.copyWith(
              streamUrl: r.streamUrl,
              quality: r.quality,
              cachedAt: r.cachedAt,
              isAvailable: true,
              title: existing.title.isNotEmpty ? existing.title : r.title,
              artist: existing.artist.isNotEmpty ? existing.artist : r.artist,
              duration: existing.duration ?? r.duration,
              thumbnailUrl: r.thumbnailUrl ?? existing.thumbnailUrl,
            );
          }
        }
      } catch (_) {}
      if (requestId != _loadRequestId) return;
      _enqueueInsertion(() => _appendContiguousReadyTail(maxToAppend: 2));
    }();
  }

  Future<void> _appendContiguousReadyTail({int maxToAppend = 2}) async {
    if (maxToAppend <= 0) return;
    if (_player.shuffleModeEnabled) return;

    final currentSource = _player.audioSource;
    if (currentSource is! ConcatenatingAudioSource) return;

    if (_childToPlaylistIndex.isEmpty) return;
    final lastPlaylistIndex = _childToPlaylistIndex.last;
    if (lastPlaylistIndex < 0 || lastPlaylistIndex >= _playlist.length) return;

    final indicesToAdd = <int>[];
    for (int idx = lastPlaylistIndex + 1;
        idx < _playlist.length && indicesToAdd.length < maxToAppend;
        idx++) {
      final t = _playlist[idx];
      if (!t.isReady || t.streamUrl == null) break; // keep contiguous window
      indicesToAdd.add(idx);
    }
    if (indicesToAdd.isEmpty) return;

    final sources = <AudioSource>[];
    for (final idx in indicesToAdd) {
      final t = _playlist[idx];
      final raw = t.streamUrl!;
      final uri = _toPlayableUri(raw, isLocal: _looksLikeFilePath(raw));
      final headers = _headersForPlayableUri(uri);
      final tag = MediaItem(
        id: t.videoId,
        title: t.title,
        artist: t.artist,
        duration: t.duration,
        artUri: t.thumbnailUrl != null ? Uri.tryParse(t.thumbnailUrl!) : null,
        extras: {'videoId': t.videoId, 'isLocal': t.isLocal},
      );

      final useCache = _shouldUseCacheForPlayableUri(uri);
      if (useCache) {
        sources.add(
          LockCachingAudioSource(
            uri,
            tag: tag,
            headers: headers,
          ),
        );
      } else {
        sources.add(AudioSource.uri(uri, tag: tag, headers: headers));
      }
    }

    await currentSource.addAll(sources);
    _childToPlaylistIndex = [..._childToPlaylistIndex, ...indicesToAdd];
  }

  // Serialize insertion operations to avoid race conditions with just_audio internal queue
  void _enqueueInsertion(Future<void> Function() op) {
    _insertionQueue = _insertionQueue.then((_) => op()).catchError((_) {});
  }

  Future<void> _insertResolvedTrack(int playlistIndex) async {
    if (playlistIndex < 0 || playlistIndex >= _playlist.length) return;
    if (!(_playlist[playlistIndex].isReady &&
        _playlist[playlistIndex].streamUrl != null)) {
      return;
    }

    // Prefer cheap tail-append to avoid stutters/restarts.
    await _appendContiguousReadyTail(maxToAppend: 6);
    _materializedIndices.add(playlistIndex);
  }

  void _handleWorkerMessage(Map<String, dynamic> message) {
    final type = message['type'];
    if (type != 'progress' && type != 'done') {
      return; // only handle progressive events
    }
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
    _preparingSubject.add(value);
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
        'quality': SettingsService().preferredQuality,
        'resolverPref': SettingsService().streamingResolverPreference.prefValue,
        'priorityIndex': _currentIndex,
        'batchSize': initialFastMode ? 3 : 6,
        'concurrency': 4,
      });

      // Listen for progress via existing receive port listener path
      // We piggyback on rp listener which will put messages through the completer remove logic.
      // We'll intercept messages by extending listener logic (below) â€“ add handler here via microtask polling.

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

    try {
      _imageCacheService.clearCache();
    } catch (_) {}
    try {
      _streamingService.clearExpiredCache();
    } catch (_) {}
  }

  // Expose equalizer
  AndroidEqualizer get equalizer => _equalizer;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  };
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
