/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/services/homeservice.dart';

class HomeState extends Equatable {
  final HomeData? homeData;
  final bool isLoading;
  final bool isInitialized;
  final String? error;
  final HomeDataSource servedFrom;
  final bool isStale;

  const HomeState({
    this.homeData,
    this.isLoading = false,
    this.isInitialized = false,
    this.error,
    this.servedFrom = HomeDataSource.fresh,
    this.isStale = false,
  });

  HomeState copyWith({
    HomeData? homeData,
    bool? isLoading,
    bool? isInitialized,
    String? error,
    HomeDataSource? servedFrom,
    bool? isStale,
  }) {
    return HomeState(
      homeData: homeData ?? this.homeData,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error ?? this.error,
      servedFrom: servedFrom ?? this.servedFrom,
      isStale: isStale ?? this.isStale,
    );
  }

  @override
  List<Object?> get props =>
      [homeData, isLoading, isInitialized, error, servedFrom, isStale];
}

