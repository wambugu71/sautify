/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:sautifyv2/apis/music_api.dart';

void main() async {
  String vidID = 'J_6BxoBt7n8';
  Api api = Api();
  print('Testing Music API');
  print(await api.getDownloadUrl(vidID));
  print('------');
  print(api.getMetadata.title);
  print(api.getMetadata.downloadUrl);
  print(api.getMetadata.duration);
  print(api.getMetadata.formart);
  print(api.getMetadata.quality);
  print(api.getMetadata.thumbnail);
  print(api.getMetadata.videoId);
}
