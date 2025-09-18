/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
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
