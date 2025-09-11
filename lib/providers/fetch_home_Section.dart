import 'package:flutter/material.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/services/homeservice.dart';

class HomeNotifier extends ChangeNotifier {
  final HomeScreenService _homeScreenService = HomeScreenService();

  bool _isInitialized = false;
  String? _error;

  HomeNotifier() {
    _initializeAndFetch();
  }

  Future<void> _initializeAndFetch() async {
    try {
      await _homeScreenService.initialize();
      _isInitialized = true;
      notifyListeners();

      await fetchHomeSections();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> fetchHomeSections() async {
    if (!_isInitialized) return;

    try {
      _error = null;
      notifyListeners();

      await _homeScreenService.getHomeSections();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  HomeData? get homeData => _homeScreenService.homeData;
  bool get isLoading => _homeScreenService.isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;

  List<Section> get sections => homeData?.sections ?? [];
}
