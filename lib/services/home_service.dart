/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:sautifyv2/models/home/home.dart';

abstract class HomeService {
  Future<void> initialize();
  HomeData? get homeData;
  bool get isLoading;
  Future<void> getHomeSections();
}
