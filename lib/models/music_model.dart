/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

class MusicMetadata {
  String title;
  String formart;
  String thumbnail;
  String downloadUrl;
  String videoId;
  int duration;
  String quality;

  MusicMetadata({
    required this.title,
    required this.formart,
    required this.thumbnail,
    required this.downloadUrl,
    required this.videoId,
    required this.duration,
    required this.quality,
  });

  factory MusicMetadata.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> data = json['result']['data'];
    //Map<String, dynamic> data = result['data'];
    return MusicMetadata(
      title: data['title'],
      formart: data['format'],
      thumbnail: data['thumbnail'],
      downloadUrl: data['downloadUrl'],
      videoId: data['videoId'],
      duration: data['duration'],
      quality: data['quality'],
    );
  }
}

/*{
  "status": true,
  "creator": "Keithkeizzah",
  "result": {
    "success": true,
    "data": {
      "title": "Wakadinali - â€œZa Kimothoâ€ (Official Music Video)",
      "type": "audio",
      "format": "mp3",
      "thumbnail": "https://i.ytimg.com/vi/6HBVh_hloAc/maxresdefault.jpg",
      "downloadUrl": "https://cdn405.savetube.su/media/6HBVh_hloAc/wakadinali-za-kimotho-official-music-video-128-ytshorts.savetube.me.mp3",
      "videoId": "6HBVh_hloAc",
      "duration": 276,
      "quality": "128"
    }
  }
*/

