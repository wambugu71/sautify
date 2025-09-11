import 'package:sautifyv2/models/home/home.dart';

abstract class HomeService {
  Future<void> initialize();
  HomeData? get homeData;
  bool get isLoading;
  Future<void> getHomeSections();
}
