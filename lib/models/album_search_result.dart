/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

class AlbumSearchResult {
  final String albumId;
  final String? playlistId;
  final String title;
  final String artist;
  final String? thumbnailUrl;

  const AlbumSearchResult({
    required this.albumId,
    this.playlistId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
  });
}

