import 'package:dio/dio.dart';

import '../config/env_config.dart';

/// Thin wrapper around [Dio] shared by every feature's repository layer.
///
/// Interceptors (auth token injection, tenant/org header, logging, error
/// normalization) are attached here so individual repositories stay
/// focused on request shaping and response parsing.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // TODO: attach auth bearer token + X-Org-Id tenant header.
          return handler.next(options);
        },
        onError: (error, handler) {
          // TODO: normalize errors into AppException (see core/errors).
          return handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;

  Dio get dio => _dio;
}
