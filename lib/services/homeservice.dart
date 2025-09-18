/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/services/home_service.dart';

class HomeScreenService implements HomeService {
  final YTMusic ytmusic = YTMusic();
  bool _isLoading = false;
  HomeData? _homeData;

  @override
  Future<void> getHomeSections() async {
    _isLoading = true;
    try {
      List<dynamic> rawSections = await ytmusic.getHomeSections();
      _homeData = HomeData.fromYTMusicSections(rawSections);
    } catch (e) {
      print('Error fetching home sections: $e');
      _homeData = null;
    } finally {
      _isLoading = false;
    }
  }

  @override
  Future<void> initialize() async {
    try {
      await ytmusic.initialize();
    } catch (e) {
      print('Error initializing YTMusic: $e');
    }
  }

  @override
  HomeData? get homeData => _homeData;

  @override
  bool get isLoading => _isLoading;
}
