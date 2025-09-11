import 'package:sautifyv2/models/music_model.dart';

abstract class MusicAPI {
  Future<String> getDownloadUrl(String videoId);
  MusicMetadata get getMetadata;
}
