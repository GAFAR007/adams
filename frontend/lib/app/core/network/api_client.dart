/// WHAT: Wraps Dio for the app's authenticated and unauthenticated backend calls.
/// WHY: Centralized HTTP behavior keeps auth headers, base URLs, and error parsing consistent.
/// HOW: Hold a mutable access token, expose typed JSON helpers, and translate Dio errors into safe exceptions.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import 'browser_adapter.dart'
    if (dart.library.js_interop) 'browser_adapter_web.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          headers: const <String, String>{'Accept': 'application/json'},
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ) {
    configureBrowserAdapter(_dio);
  }

  final Dio _dio;

  void setAccessToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }

    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Object>(
        path,
        queryParameters: queryParameters,
      );
      return _normalizeResponse(response.data);
    } on DioException catch (error) {
      final fallbackResponse = await _retryWithLoopbackFallback(
        error,
        () => _dio.get<Object>(path, queryParameters: queryParameters),
      );

      if (fallbackResponse != null) {
        return _normalizeResponse(fallbackResponse.data);
      }

      throw ApiException(_extractMessage(error));
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post<Object>(path, data: data);
      return _normalizeResponse(response.data);
    } on DioException catch (error) {
      final fallbackResponse = await _retryWithLoopbackFallback(
        error,
        () => _dio.post<Object>(path, data: data),
      );

      if (fallbackResponse != null) {
        return _normalizeResponse(fallbackResponse.data);
      }

      throw ApiException(_extractMessage(error));
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.patch<Object>(path, data: data);
      return _normalizeResponse(response.data);
    } on DioException catch (error) {
      final fallbackResponse = await _retryWithLoopbackFallback(
        error,
        () => _dio.patch<Object>(path, data: data),
      );

      if (fallbackResponse != null) {
        return _normalizeResponse(fallbackResponse.data);
      }

      throw ApiException(_extractMessage(error));
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final response = await _dio.delete<Object>(path);
      return _normalizeResponse(response.data);
    } on DioException catch (error) {
      final fallbackResponse = await _retryWithLoopbackFallback(
        error,
        () => _dio.delete<Object>(path),
      );

      if (fallbackResponse != null) {
        return _normalizeResponse(fallbackResponse.data);
      }

      throw ApiException(_extractMessage(error));
    }
  }

  void dispose() {
    _dio.close(force: true);
  }

  Map<String, dynamic> _normalizeResponse(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is String && data.isNotEmpty) {
      return jsonDecode(data) as Map<String, dynamic>;
    }

    return const <String, dynamic>{};
  }

  Future<Response<Object>?> _retryWithLoopbackFallback(
    DioException error,
    Future<Response<Object>> Function() request,
  ) async {
    // WHY: Only retry browser-style network failures, because real backend responses should surface unchanged.
    if (!_isRetryableNetworkError(error)) {
      return null;
    }

    final alternateBaseUrl = _buildAlternateLoopbackBaseUrl();
    if (alternateBaseUrl == null || alternateBaseUrl == _dio.options.baseUrl) {
      return null;
    }

    final previousBaseUrl = _dio.options.baseUrl;
    debugPrint(
      'ApiClient._retryWithLoopbackFallback: retrying from $previousBaseUrl to $alternateBaseUrl',
    );

    try {
      // WHY: Switch to the alternate loopback host so localhost/127.0.0.1 resolution issues do not block local development.
      _dio.options.baseUrl = alternateBaseUrl;
      return await request();
    } on DioException {
      // WHY: Restore the previous base URL when the fallback also fails so later errors remain truthful.
      _dio.options.baseUrl = previousBaseUrl;
      return null;
    }
  }

  bool _isRetryableNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  String? _buildAlternateLoopbackBaseUrl() {
    final currentBaseUrl = Uri.tryParse(_dio.options.baseUrl);
    if (currentBaseUrl == null) {
      return null;
    }

    if (currentBaseUrl.host == 'localhost') {
      // WHY: Try the IPv4 loopback host when localhost resolution is the part that is failing in the browser.
      return currentBaseUrl.replace(host: '127.0.0.1').toString();
    }

    if (currentBaseUrl.host == '127.0.0.1') {
      // WHY: Allow the reverse fallback too so whichever loopback host is reachable becomes sticky for later calls.
      return currentBaseUrl.replace(host: 'localhost').toString();
    }

    return null;
  }

  String _extractMessage(DioException error) {
    final responseData = error.response?.data;

    if (responseData is Map<String, dynamic>) {
      final safeMessage = responseData['message'];
      final hint = responseData['resolution_hint'];

      if (safeMessage is String && hint is String && hint.isNotEmpty) {
        return '$safeMessage\n$hint';
      }

      if (safeMessage is String && safeMessage.isNotEmpty) {
        return safeMessage;
      }
    }

    return error.message ?? 'The request failed';
  }
}
