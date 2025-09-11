class Contents {
  final String name;
  final String artistName;
  final String type;
  final String? playlistId;
  final String thumbnailUrl;

  Contents({
    required this.name,
    required this.artistName,
    required this.type,
    this.playlistId,
    required this.thumbnailUrl,
  });

  factory Contents.fromYTMusicContent(dynamic content) {
    // Prefer medium/high thumbnail: pick the second if present, else the last
    String resolvedThumb = '';
    final thumbs = content.thumbnails;
    if (thumbs != null && thumbs.isNotEmpty) {
      if (thumbs.length >= 2) {
        resolvedThumb = thumbs[1].url;
      } else {
        resolvedThumb = thumbs.last.url;
      }
    }

    return Contents(
      name: content.name ?? '',
      artistName: content.artist?.name ?? 'Unknown Artist',
      type: content.type ?? '',
      playlistId: content.playlistId,
      thumbnailUrl: resolvedThumb,
    );
  }

  @override
  String toString() {
    return 'Contents(name: $name, artist: $artistName, type: $type)';
  }
}
