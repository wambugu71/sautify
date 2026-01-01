import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sautifyv2/blocs/settings/settings_cubit.dart';
import 'package:sautifyv2/fetch_music_data.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/services/download_service.dart';

import '../../isolate/download_finalize_worker.dart';
import 'download_state.dart';

class DownloadCubit extends Cubit<DownloadState> {
  Box<String>? _downloadsBox;
  final SettingsCubit _settingsCubit;
  final MusicStreamingService _streamingService = MusicStreamingService();

  DownloadCubit(this._settingsCubit) : super(const DownloadState());

  Future<void> init() async {
    try {
      await Hive.initFlutter();
    } catch (_) {}
    _downloadsBox = Hive.isBoxOpen('downloads_box')
        ? Hive.box<String>('downloads_box')
        : await Hive.openBox<String>('downloads_box');

    emit(state.copyWith(isInitialized: true));
    await checkPermissionAndLoad();
  }

  Future<void> checkPermissionAndLoad() async {
    emit(state.copyWith(isLoading: true));
    try {
      // Downloads are managed via app-controlled directories and Hive metadata,
      // so we don't require runtime storage permissions.
      emit(state.copyWith(hasPermission: true));
      await loadSongs();
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    } finally {
      emit(state.copyWith(isLoading: false));
    }
  }

  void _emitEvent(String message, {required bool isError}) {
    emit(
      state.copyWith(
        eventId: (state.eventId ?? 0) + 1,
        eventVideoId: state.activeDownloadVideoId,
        eventMessage: message,
        eventIsError: isError,
      ),
    );
  }

  void _emitTargetedEvent(
    String videoId,
    String message, {
    required bool isError,
  }) {
    emit(
      state.copyWith(
        eventId: (state.eventId ?? 0) + 1,
        eventVideoId: videoId,
        eventMessage: message,
        eventIsError: isError,
      ),
    );
  }

  // Tagging/rename work is offloaded to a compute isolate.

  Future<void> loadSongs() async {
    try {
      final box = _downloadsBox;
      if (box == null) return;

      final entries = box.toMap().entries.toList(growable: false);
      final parsed = <({StreamingData track, DateTime? downloadedAt})>[];

      for (final entry in entries) {
        final t = _streamingDataFromBox(entry.key, entry.value);
        if (t == null) continue;

        DateTime? downloadedAt;
        try {
          final decoded = jsonDecode(entry.value) as Map<String, dynamic>;
          final dt = decoded['downloadedAt'] as String?;
          if (dt != null) downloadedAt = DateTime.tryParse(dt);
        } catch (_) {}

        parsed.add((track: t, downloadedAt: downloadedAt));
      }

      parsed.sort((a, b) {
        final da = a.downloadedAt;
        final db = b.downloadedAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      emit(
        state.copyWith(
          downloadedTracks: parsed.map((e) => e.track).toList(growable: false),
        ),
      );
    } catch (e) {
      // Handle error
    }
  }

  Future<void> downloadTrack(StreamingData track) async {
    if (state.downloadingIds.contains(track.videoId)) return;

    if (!state.isInitialized) {
      _emitEvent('Downloads are not ready yet', isError: true);
      return;
    }

    if (isDownloaded(track.videoId)) {
      _emitEvent('Already downloaded', isError: false);
      return;
    }

    setDownloading(track.videoId, true);
    emit(
      state.copyWith(
        activeDownloadVideoId: track.videoId,
        progressReceived: 0,
        progressTotal: 0,
      ),
    );
    _emitTargetedEvent(track.videoId, 'Downloading…', isError: false);

    try {
      final streamingData = await _streamingService.fetchStreamingData(
        track.videoId,
        StreamingQuality.high,
      );

      final url = streamingData?.streamUrl;
      if (url == null || url.isEmpty) {
        throw Exception('Could not get streaming URL');
      }

      final downloadDir = await _resolveDownloadDirectory();
      final ext = _inferAudioExtensionFromUrl(url);
      final safeTitle = _sanitizeFileName(track.title);
      final safeArtist = _sanitizeFileName(track.artist);
      final fileName = '$safeTitle - $safeArtist$ext';
      final savePath = _joinPath(downloadDir.path, fileName);

      await DownloadService.startDownload(
        url: url,
        savePath: savePath,
        onProgress: (received, total) {
          // Track progress for UI.
          if (state.activeDownloadVideoId == track.videoId) {
            emit(
              state.copyWith(
                progressReceived: received,
                progressTotal: total,
              ),
            );
          }
        },
        onDone: () {
          setDownloading(track.videoId, false);
          () async {
            // Offload rename + optional cover fetch + tag writing.
            final result = await compute(
              finalizeDownloadedFile,
              <String, dynamic>{
                'filePath': savePath,
                'title': track.title,
                'artist': track.artist,
                'thumbnailUrl': track.thumbnailUrl,
              },
            );
            final actualPath = (result['finalPath'] as String?) ?? savePath;
            final taggingAttempted =
                (result['taggingAttempted'] as bool?) ?? false;
            final taggingOk = (result['taggingOk'] as bool?) ?? true;

            if (taggingAttempted && !taggingOk) {
              _emitTargetedEvent(
                track.videoId,
                'Downloaded, but tagging failed',
                isError: true,
              );
            }

            // Best-effort: update MediaStore index so device library picks it up.
            try {
              await OnAudioQuery().scanMedia(actualPath);
            } catch (_) {}

            await markAsDownloaded(track, actualPath);
            _emitTargetedEvent(track.videoId, 'Downloaded', isError: false);
          }()
              .catchError((e) {
            debugPrint('post-download finalize failed: $e');
            _emitTargetedEvent(
              track.videoId,
              'Download finished, but saving failed',
              isError: true,
            );
          });
        },
        onError: (error) {
          setDownloading(track.videoId, false);
          debugPrint('Download failed: $error');
          _emitTargetedEvent(track.videoId, error, isError: true);
        },
      );
    } catch (e) {
      setDownloading(track.videoId, false);
      debugPrint('downloadTrack failed: $e');
      _emitTargetedEvent(track.videoId, e.toString(), isError: true);
    }
  }

  void setDownloading(String videoId, bool isDownloading) {
    final newIds = Set<String>.from(state.downloadingIds);
    if (isDownloading) {
      newIds.add(videoId);
    } else {
      newIds.remove(videoId);
    }
    emit(state.copyWith(downloadingIds: newIds));
  }

  bool isDownloaded(String videoId) {
    return _downloadsBox?.containsKey(videoId) ?? false;
  }

  Future<void> markAsDownloaded(StreamingData track, String filePath) async {
    final metaJson = {
      'videoId': track.videoId,
      'title': track.title,
      'artist': track.artist,
      'artPath': null,
      'imageUrl': track.thumbnailUrl,
      'filePath': filePath,
      'downloadedAt': DateTime.now().toIso8601String(),
    };

    await _downloadsBox?.put(track.videoId, jsonEncode(metaJson));
    await loadSongs();
  }

  StreamingData? _streamingDataFromBox(String videoId, String value) {
    // New format: JSON metadata (matches `home_screen.dart`).
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final filePath = data['filePath'] as String?;
      if (filePath == null || filePath.isEmpty) return null;

      final title = (data['title'] as String?) ?? 'Unknown Title';
      final artist = (data['artist'] as String?) ?? 'Unknown Artist';
      final thumb =
          (data['artPath'] as String?) ?? (data['imageUrl'] as String?);
      final exists = File(filePath).existsSync();

      return StreamingData(
        videoId: (data['videoId'] as String?) ?? videoId,
        title: title,
        artist: artist,
        thumbnailUrl: thumb,
        streamUrl: filePath,
        isLocal: true,
        isAvailable: exists,
      );
    } catch (_) {
      // Legacy format: plain file path.
      final filePath = value;
      if (filePath.isEmpty) return null;
      final exists = File(filePath).existsSync();
      return StreamingData(
        videoId: videoId,
        title: 'Downloaded Track',
        artist: 'Unknown Artist',
        thumbnailUrl: null,
        streamUrl: filePath,
        isLocal: true,
        isAvailable: exists,
      );
    }
  }

  String? _filePathFromBoxValue(String videoId) {
    final box = _downloadsBox;
    if (box == null) return null;

    final value = box.get(videoId);
    if (value == null || value.isEmpty) return null;

    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final filePath = (data['filePath'] as String?)?.trim();
      if (filePath == null || filePath.isEmpty) return null;
      return filePath;
    } catch (_) {
      // Legacy format: plain file path.
      return value.trim().isEmpty ? null : value.trim();
    }
  }

  Future<bool> deleteDownload(String videoId) async {
    final box = _downloadsBox;
    if (box == null) return false;

    try {
      final path = _filePathFromBoxValue(videoId);
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {
          // Best-effort: still remove the metadata entry.
        }
      }

      await box.delete(videoId);
      await loadSongs();
      return true;
    } catch (e) {
      debugPrint('deleteDownload failed: $e');
      return false;
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    final configured = _settingsCubit.state.downloadPath;
    final defaultDir = await _defaultDownloadDirectory();

    if (configured.isEmpty) {
      _settingsCubit.setDownloadPath(defaultDir.path);
      return defaultDir;
    }

    try {
      final dir = Directory(configured);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      _settingsCubit.setDownloadPath(defaultDir.path);
      return defaultDir;
    }
  }

  Future<Directory> _defaultDownloadDirectory() async {
    if (Platform.isAndroid) {
      final preferred = Directory('/storage/emulated/0/Music');
      try {
        if (!await preferred.exists()) {
          await preferred.create(recursive: true);
        }
        return preferred;
      } catch (_) {
        // Fall back to app-controlled directory.
      }
    }

    final Directory baseDir = Platform.isAndroid
        ? (await getExternalStorageDirectory()) ??
            await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();

    final dir = Directory(_joinPath(baseDir.path, 'Sautify/Downloads'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _inferAudioExtensionFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('mime=audio%2fwebm') ||
        u.contains('audio/webm') ||
        u.endsWith('.webm')) {
      return '.webm';
    }
    if (u.contains('mime=audio%2fmp4') ||
        u.contains('audio/mp4') ||
        u.endsWith('.m4a')) {
      return '.m4a';
    }
    return '.mp3';
  }

  String _sanitizeFileName(String s) {
    final illegal = RegExp(r'[\\/:*?"<>|]');
    final cleaned = s.replaceAll(illegal, '_').trim();
    if (cleaned.isEmpty) return 'Unknown';
    return cleaned.length > 160 ? cleaned.substring(0, 160) : cleaned;
  }

  String _joinPath(String a, String b) {
    if (a.isEmpty) return b;
    final sep = Platform.pathSeparator;
    final left = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
    final right = b.startsWith(sep) ? b.substring(1) : b;
    return '$left$sep$right';
  }
}
