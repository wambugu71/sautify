/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
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
