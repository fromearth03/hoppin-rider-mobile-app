import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import '../device/device_id.dart';
import '../result.dart';
import 'api_exception.dart';

/// Every call to the ride service goes through here. Returns [Result] rather
/// than throwing, so callers handle failure where it happens.
class ApiClient {
  static const _defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL',
          defaultValue: 'https://api.hoppin.tech/api/v1');

  final Dio _dio;
  final TokenStore _tokens;
  final DeviceIdProvider _device;

  ApiClient(this._dio, this._tokens, this._device, {String? baseUrl}) {
    _dio.options.baseUrl = baseUrl ?? _defaultBaseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    // Longer than the backend's 4 s Photon timeout, so we never cancel work the
    // server would have finished.
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    // Let non-2xx through so the envelope can be parsed rather than thrown.
    _dio.options.validateStatus = (_) => true;

    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        final token = await _tokens.read();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';

        // The blacklist gate is fail-open on a missing header, so omitting this
        // silently disables it. Always send one.
        options.headers['X-Hoppin-Device-ID'] = await _device.resolve();

        handler.next(options);
      }),
    );
  }

  Future<Result<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>(() => _dio.get(path, queryParameters: query));

  Future<Result<T>> post<T>(String path,
          {Object? body, Map<String, dynamic>? query}) =>
      _send<T>(() => _dio.post(path, data: body, queryParameters: query));

  Future<Result<T>> patch<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.patch(path, data: body));

  Future<Result<T>> delete<T>(String path, {Object? body}) =>
      _send<T>(() => _dio.delete(path, data: body));

  /// Multipart upload with the same auth the JSON calls get — the shape
  /// `POST /me/avatar/upload` expects (`file` form field).
  Future<Result<T>> postFile<T>(
    String path, {
    required Uint8List bytes,
    String field = 'file',
    String filename = 'upload.jpg',
  }) =>
      _send<T>(() => _dio.post(
            path,
            data: FormData.fromMap({
              field: MultipartFile.fromBytes(bytes, filename: filename),
            }),
          ));

  /// Raw bytes with the same auth the JSON calls get. The image routes
  /// require a bearer token, which a plain `NetworkImage` (an `<img>` tag on
  /// web) cannot send — so images that need auth come through here instead.
  Future<Result<Uint8List>> getBytes(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final status = response.statusCode ?? 500;
      final data = response.data;
      if (status >= 200 && status < 300 && data != null) {
        return Ok(Uint8List.fromList(data));
      }
      return Err(
          ApiException(status >= 500 ? 'INTERNAL' : 'NOT_FOUND', '', status));
    } on DioException catch (e) {
      return Err(ApiException('INTERNAL', e.message ?? 'network error', 0));
    }
  }

  Future<Result<T>> _send<T>(Future<Response> Function() call) async {
    try {
      final response = await call();
      final status = response.statusCode ?? 500;
      if (status >= 200 && status < 300) {
        return Ok<T>(response.data as T);
      }
      return Err<T>(parseError(response));
    } on DioException catch (e) {
      // Timeouts and connection failures are transient. INTERNAL is the honest
      // classification for "no network" — it is the one code we mark retryable
      // without the server having said so.
      return Err<T>(ApiException('INTERNAL', e.message ?? 'network error', 0));
    }
  }

  /// Reads `{"error": ..., "code": ...}`, keeping any extra top-level keys
  /// (`blockers`, `seconds`, `reason`) that specific codes add.
  static ApiException parseError(Response response) {
    final status = response.statusCode ?? 500;
    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = null;
      }
    }
    if (data is! Map) {
      return ApiException(status >= 500 ? 'INTERNAL' : 'NOT_FOUND', '', status);
    }
    final map = Map<String, dynamic>.from(data);
    final extras = Map<String, dynamic>.from(map)
      ..remove('code')
      ..remove('error');
    return ApiException(
      (map['code'] as String?) ?? (status >= 500 ? 'INTERNAL' : 'NOT_FOUND'),
      (map['error'] as String?) ?? '',
      status,
      fields: extras,
    );
  }
}

final dioProvider = Provider<Dio>((ref) => Dio());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(deviceIdProvider),
  ),
);
