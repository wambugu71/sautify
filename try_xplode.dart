import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  var yt = YoutubeExplode();

  var manifest = await yt.videos.streams.getManifest('2lwqoQ9dZs4');

  print(manifest);

  // highest bitrate audio-only stream
  var streamInfo = manifest.audioOnly.withHighestBitrate();
  print(streamInfo.qualityLabel);
  print(streamInfo.url);

  yt.close();
  return;
}
