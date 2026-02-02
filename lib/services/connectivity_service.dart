/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal() {
    _init();
  }

  final _onlineSubject = BehaviorSubject<bool>.seeded(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ValueStream<bool> get isOnline$ =>
      _onlineSubject.stream.shareValueSeeded(true);

  Future<void> _init() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      final online =
          initial.isNotEmpty &&
          initial.any((c) => c != ConnectivityResult.none);
      _onlineSubject.add(online);
    } catch (_) {}

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online =
          results.isNotEmpty &&
          results.any((c) => c != ConnectivityResult.none);
      if (_onlineSubject.valueOrNull != online) {
        _onlineSubject.add(online);
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _onlineSubject.close();
  }
}

