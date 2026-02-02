/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sautifyv2/services/homeservice.dart';

import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final HomeScreenService _homeScreenService = HomeScreenService();

  HomeCubit() : super(const HomeState()) {
    _initializeAndFetch();
  }

  Future<void> _initializeAndFetch() async {
    try {
      emit(state.copyWith(isLoading: true));
      await _homeScreenService.initialize();
      emit(state.copyWith(isInitialized: true));
      await fetchHomeSections();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  Future<void> fetchHomeSections() async {
    if (!state.isInitialized) return;

    try {
      emit(state.copyWith(error: null, isLoading: true));
      await _homeScreenService.getHomeSections();
      _updateFromService();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  void _updateFromService() {
    emit(state.copyWith(
      homeData: _homeScreenService.homeData,
      isLoading: _homeScreenService.isLoading,
      servedFrom: _homeScreenService.servedFrom,
      isStale: _homeScreenService.isStale,
    ));
  }

  Future<void> refresh({Duration? timeout}) async {
    emit(state.copyWith(isLoading: true));
    await _homeScreenService.refresh(timeout: timeout);
    _updateFromService();
  }
}

