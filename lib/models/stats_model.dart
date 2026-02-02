/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

class SongStats {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  int playCount;
  DateTime lastPlayed;

  SongStats({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.playCount = 0,
    required this.lastPlayed,
  });

  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'playCount': playCount,
      'lastPlayed': lastPlayed.millisecondsSinceEpoch,
    };
  }

  factory SongStats.fromJson(Map<String, dynamic> json) {
    return SongStats(
      videoId: json['videoId'],
      title: json['title'],
      artist: json['artist'],
      thumbnailUrl: json['thumbnailUrl'],
      playCount: json['playCount'] ?? 0,
      lastPlayed: DateTime.fromMillisecondsSinceEpoch(json['lastPlayed']),
    );
  }
}

