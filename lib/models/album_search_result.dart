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
