/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

class DioClient {
  DioClient._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      contentType: 'application/json',
    ),
  );

  static bool _configured = false;

  static Dio get instance {
    if (!_configured) {
      // Smart retry: timeouts/connection errors + 5xx
      _dio.interceptors.add(
        RetryInterceptor(
          dio: _dio,
          retries: 2,
          retryDelays: const [
            Duration(milliseconds: 500),
            Duration(seconds: 1),
          ],
          retryEvaluator: (error, attempt) {
            if (error.type == DioExceptionType.cancel) return false;
            if (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout ||
                error.type == DioExceptionType.connectionError) {
              return true;
            }
            final status = error.response?.statusCode ?? 0;
            return status >= 500 && status < 600;
          },
        ),
      );

      if (kDebugMode) {
        _dio.interceptors.add(
          LogInterceptor(
            requestBody: false,
            responseBody: false,
            requestHeader: false,
          ),
        );
      }

      _configured = true;
    }
    return _dio;
  }

  static Future<void> init() async {
    // No special initialization needed for standard Dio
  }
}

