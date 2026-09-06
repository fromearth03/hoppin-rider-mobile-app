import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import '../device/device_id.dart';
import '../net/network_status.dart';
import '../result.dart';
import 'api_exception.dart';

/// Every call to the ride service goes through here. Returns [Result] rather
/// than throwing, so callers handle failure where it happens.
class ApiClient {
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hoppin.tech/api/v1',
  );

  final Dio _dio;
  final TokenStore _tokens;
  final DeviceIdProvider _device;

  /// Told, after every call, whether the server was actually reached. This is
  /// what drives the offline screen: a real HTTP response — even a 500 — proves
  /// the network is fine, while a transport failure means we could not get
  /// there at all. Optional so tests and tooling need no wiring.
  final void Function({required bool reachedServer})? onReachability;

  ApiClient(
    this._dio,
    this._tokens,
    this._device, {
    String? baseUrl,
    this.onReachability,
  }) {
    _dio.options.baseUrl = baseUrl ?? _defaultBaseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    // Longer than the backend's 4 s Photon timeout, so we never cancel work the
    // server would have finished.
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    // Let non-2xx through so the envelope can be parsed rather than thrown.
    _dio.options.validateStatus = (_) => true;

    // Replace rather than append. The Dio instance is a shared singleton, so a
    // second ApiClient over the same Dio used to leave BOTH interceptors in the
    // chain, each independently reading the token on every request.
    _dio.interceptors.removeWhere((i) => i is _HoppinHeaders);
    _dio.interceptors.add(_HoppinHeaders(_tokens, _device));
  }

  Future<Result<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>(() => _dio.get(path, queryParameters: query));

  Future<Result<T>> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => _send<T>(() => _dio.post(path, data: body, queryParameters: query));

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
  }) => _send<T>(
    () => _dio.post(
      path,
      data: FormData.fromMap({
        field: MultipartFile.fromBytes(bytes, filename: filename),
      }),
    ),
  );

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
        ApiException(status >= 500 ? 'INTERNAL' : 'NOT_FOUND', '', status),
      );
    } on DioException catch (e) {
      return Err(ApiException('INTERNAL', e.message ?? 'network error', 0));
    }
  }

  Future<Result<T>> _send<T>(Future<Response> Function() call) async {
    try {
      final response = await call();
      // Any status at all means we got through to the server.
      onReachability?.call(reachedServer: true);
      final status = response.statusCode ?? 500;
      if (status >= 200 && status < 300) {
        return Ok<T>(response.data as T);
      }
      return Err<T>(parseError(response));
    } on DioException catch (e) {
      // Timeouts and connection failures are transient. INTERNAL is the honest
      // classification for "no network" — it is the one code we mark retryable
      // without the server having said so.
      //
      // Only a TRANSPORT failure counts as offline. A cancellation is the app's
      // own doing and says nothing about the network.
      if (e.type != DioExceptionType.cancel) {
        onReachability?.call(reachedServer: false);
      }
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

/// Attaches the auth and device headers to every request.
///
/// A named type rather than an inline `InterceptorsWrapper` so a rebuilt client
/// can find and replace its own interceptor instead of stacking another one.
class _HoppinHeaders extends Interceptor {
  final TokenStore _tokens;
  final DeviceIdProvider _device;

  _HoppinHeaders(this._tokens, this._device);

  /// How long the headers may take before the request goes without them.
  ///
  /// Dio's connectTimeout does not start until the connection is attempted, so
  /// anything awaited HERE is outside every timeout the client has: a stalled
  /// token refresh or device-id lookup blocks the request before it is sent,
  /// forever, and the screen waiting on it never leaves its loading state.
  /// Sending an unauthenticated request is recoverable — a 401 the app already
  /// handles. Never sending one is not.
  /// Comfortably longer than TokenStore's own 5s refresh bound, so in the
  /// normal stalled-refresh case that fallback wins and the request still
  /// carries the stale token. This is the backstop for the case nothing else
  /// catches.
  static const _headerBudget = Duration(seconds: 8);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await _tokens.read().timeout(_headerBudget);
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    } catch (_) {
      // Go without it; the server decides.
    }
    try {
      // The blacklist gate is fail-open on a missing header, so omitting this
      // silently disables it. Always send one when we can get one.
      options.headers['X-Hoppin-Device-ID'] =
          await _device.resolve().timeout(_headerBudget);
    } catch (_) {
      // Same trade: a request without the header beats no request at all.
    }
    handler.next(options);
  }
}

final dioProvider = Provider<Dio>((ref) => Dio());

final apiClientProvider = Provider<ApiClient>((ref) {
  // read, NOT watch. The client only calls a method on this notifier; watching
  // it rebuilt the whole client every time reachability flipped, which meant a
  // new interceptor on the shared Dio each time.
  final status = ref.read(networkStatusProvider);
  final client = ApiClient(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(deviceIdProvider),
    onReachability: status.report,
  );
  // The probe that decides when we are back. `/app-status` is public, tiny and
  // needs no token, so it works even when the session has expired.
  status.pingBackend ??= () async {
    final res = await client.get<Map<String, dynamic>>(
      '/app-status',
      query: {'platform': 'android', 'version': '1.0.0'},
    );
    return res is Ok;
  };
  return client;
});
