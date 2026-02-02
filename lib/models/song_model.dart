/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

class SongModel {
  String title;
  String artist;
  String album;
  String url;
  String id;
  String imageUrl;
  Duration duration;

  SongModel({
    required this.title,
    required this.artist,
    required this.album,
    required this.url,
    required this.id,
    required this.imageUrl,
    required this.duration,
  });
}

