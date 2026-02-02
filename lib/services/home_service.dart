/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:sautifyv2/models/home/home.dart';

abstract class HomeService {
  Future<void> initialize();
  HomeData? get homeData;
  bool get isLoading;
  Future<void> getHomeSections();
}

