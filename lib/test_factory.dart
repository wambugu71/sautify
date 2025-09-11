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
