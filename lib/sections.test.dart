/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
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

