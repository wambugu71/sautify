/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:sautifyv2/models/music_model.dart';

abstract class MusicAPI {
  Future<String> getDownloadUrl(String videoId);
  MusicMetadata get getMetadata;
}

