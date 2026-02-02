/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'streaming_model.dart';

class SavedPlaylist {
  final String id;
  final String title;
  final String? artworkUrl;
  final List<StreamingData> tracks;
  final DateTime updatedAt;

  SavedPlaylist({
    required this.id,
    required this.title,
    required this.tracks,
    this.artworkUrl,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artworkUrl': artworkUrl,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'tracks': tracks.map((e) => e.toJson()).toList(),
  };

  factory SavedPlaylist.fromJson(Map<String, dynamic> json) => SavedPlaylist(
    id: json['id'],
    title: json['title'],
    artworkUrl: json['artworkUrl'],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt']),
    tracks: (json['tracks'] as List<dynamic>)
        .map((e) => StreamingData.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class SavedAlbum {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final List<StreamingData> tracks;
  final DateTime updatedAt;

  SavedAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.tracks,
    this.artworkUrl,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'tracks': tracks.map((e) => e.toJson()).toList(),
  };

  factory SavedAlbum.fromJson(Map<String, dynamic> json) => SavedAlbum(
    id: json['id'],
    title: json['title'],
    artist: json['artist'],
    artworkUrl: json['artworkUrl'],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt']),
    tracks: (json['tracks'] as List<dynamic>)
        .map((e) => StreamingData.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

