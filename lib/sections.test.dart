/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:sautifyv2/models/home/home.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  print('Testing Sections model');

  try {
    List<dynamic> results = await ytmusic.getHomeSections();
    HomeData homeData = HomeData.fromYTMusicSections(results);

    for (var section in homeData.sections) {
      print('Section: ${section.title}');
      for (var content in section.contents) {
        print(' - ${content.name} by ${content.artistName} (${content.type})');
      }
      print('---');
    }
  } catch (e) {
    print('Error: $e');
  }
}
