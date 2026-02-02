/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/playlist_models.dart';
import 'package:sautifyv2/models/stats_model.dart';
import 'package:sautifyv2/models/streaming_model.dart';

class LibraryState extends Equatable {
  final List<StreamingData> favorites;
  final List<StreamingData> recentPlays;
  final List<SavedPlaylist> playlists;
  final List<SavedAlbum> albums;
  final List<SongStats> mostPlayed;
  final bool isReady;

  const LibraryState({
    this.favorites = const [],
    this.recentPlays = const [],
    this.playlists = const [],
    this.albums = const [],
    this.mostPlayed = const [],
    this.isReady = false,
  });

  LibraryState copyWith({
    List<StreamingData>? favorites,
    List<StreamingData>? recentPlays,
    List<SavedPlaylist>? playlists,
    List<SavedAlbum>? albums,
    List<SongStats>? mostPlayed,
    bool? isReady,
  }) {
    return LibraryState(
      favorites: favorites ?? this.favorites,
      recentPlays: recentPlays ?? this.recentPlays,
      playlists: playlists ?? this.playlists,
      albums: albums ?? this.albums,
      mostPlayed: mostPlayed ?? this.mostPlayed,
      isReady: isReady ?? this.isReady,
    );
  }

  @override
  List<Object?> get props =>
      [favorites, recentPlays, playlists, albums, mostPlayed, isReady];
}

