/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sautifyv2/models/streaming_model.dart';

import 'device_library_state.dart';

class DeviceLibraryCubit extends Cubit<DeviceLibraryState> {
  final OnAudioQuery _query;

  DeviceLibraryCubit({OnAudioQuery? query})
      : _query = query ?? OnAudioQuery(),
        super(const DeviceLibraryState());

  Future<void> init() async {
    await refresh();
  }

  Future<void> requestPermission() async {
    try {
      final granted = await _query.permissionsRequest();
      emit(state.copyWith(hasPermission: granted, error: null));
      if (granted) {
        await refresh();
      }
    } catch (e) {
      emit(state.copyWith(
        hasPermission: false,
        error: 'Permission request failed',
      ));
    }
  }

  Future<void> refresh({String? folderPath}) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final status = await _query.permissionsStatus();
      if (!status) {
        emit(state.copyWith(
          isLoading: false,
          hasPermission: false,
          tracks: const [],
        ));
        return;
      }

      final raw = await _query.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final normalizedFolder = _normalizeFolder(folderPath);

      final tracks = <StreamingData>[];
      for (final s in raw) {
        final path = s.data;
        final uri = (s.uri ?? '').trim();
        final streamRef = uri.isNotEmpty ? uri : path;
        if (streamRef.isEmpty) continue;

        if (normalizedFolder != null) {
          final normalizedPath = _normalizePath(path);
          if (!normalizedPath.startsWith(normalizedFolder)) continue;
        }

        // Some Android versions return inaccessible paths (scoped storage) but a usable content:// URI.
        // Treat content URIs as available.
        final isContentUri = streamRef.startsWith('content://');
        bool exists = true;
        if (!isContentUri && path.isNotEmpty) {
          try {
            exists = File(path).existsSync();
          } catch (_) {
            exists = true;
          }
        }

        tracks.add(
          StreamingData(
            videoId: 'local_${s.id}',
            title: (s.title).trim().isEmpty ? 'Unknown Title' : s.title,
            artist: (s.artist ?? '').trim().isEmpty
                ? 'Unknown Artist'
                : (s.artist ?? 'Unknown Artist'),
            duration:
                s.duration != null ? Duration(milliseconds: s.duration!) : null,
            streamUrl: streamRef,
            isLocal: true,
            isAvailable: exists,
            localId: s.id,
            thumbnailUrl: null,
          ),
        );
      }

      emit(state.copyWith(
        isLoading: false,
        hasPermission: true,
        tracks: tracks,
      ));
    } catch (e, st) {
      debugPrint('DeviceLibraryCubit.refresh failed: $e\n$st');
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to scan device audio',
      ));
    }
  }

  static String _normalizePath(String p) {
    // Use forward slashes for prefix matching.
    return p.replaceAll('\\', '/');
  }

  static String? _normalizeFolder(String? folderPath) {
    if (folderPath == null) return null;
    final trimmed = folderPath.trim();
    if (trimmed.isEmpty) return null;

    var normalized = _normalizePath(trimmed);
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    return normalized;
  }
}

