import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API client with automatic access-token attach + refresh on 401.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// With `adb reverse tcp:3000 tcp:3000` (USB), the phone's localhost:3000
  /// reaches the dev machine's API.
  static const String baseUrl = 'http://localhost:3000';

  final _storage = const FlutterSecureStorage();
  late final Dio dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)))
    ..interceptors.add(_AuthInterceptor(this));

  Future<String?> get accessToken => _storage.read(key: 'access_token');
  Future<String?> get refreshToken => _storage.read(key: 'refresh_token');
  Future<String?> get currentUserId => _storage.read(key: 'user_id');

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    await _storage.write(key: 'user_id', value: userId);
  }

  Future<void> clearSession() async {
    // The per-user biometric PIN is intentionally KEPT (keyed by userId),
    // so fingerprint stays enabled for that account after re-login.
    // Cross-account use is impossible because the key includes the userId.
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'user_id');
  }

  Future<bool> hasSession() async {
    return await refreshToken != null;
  }

  /// Local copy of the payment PIN for the CURRENT user, used to authorize
  /// payments after a successful biometric check. Stored per user id and
  /// wiped on logout — never shared between accounts.
  Future<void> saveLocalPin(String pin) async {
    final uid = await currentUserId;
    if (uid == null) return;
    await _storage.write(key: 'local_pin_$uid', value: pin);
  }

  Future<String?> readLocalPin() async {
    final uid = await currentUserId;
    if (uid == null) return null;
    return _storage.read(key: 'local_pin_$uid');
  }

  Future<void> clearLocalPin() async {
    final uid = await currentUserId;
    if (uid == null) return;
    await _storage.delete(key: 'local_pin_$uid');
  }

  /// App-lock preference for the CURRENT user (`app_lock_<userId>`).
  /// Default ON when no explicit preference exists but a local PIN is
  /// stored; otherwise OFF (nothing to fall back on).
  Future<bool> readAppLockEnabled() async {
    final uid = await currentUserId;
    if (uid == null) return false;
    final v = await _storage.read(key: 'app_lock_$uid');
    if (v != null) return v == 'true';
    return await readLocalPin() != null;
  }

  Future<void> saveAppLockEnabled(bool enabled) async {
    final uid = await currentUserId;
    if (uid == null) return;
    await _storage.write(key: 'app_lock_$uid', value: enabled ? 'true' : 'false');
  }

  /// Verifies a PIN against the server session. Throws [ApiException] on
  /// rejection (wrong PIN / dead session) or network problems.
  Future<void> verifyPin(String pin) async {
    try {
      final res = await dio.post('/auth/pin/verify', data: {'pin': pin});
      if (res.data is Map && res.data['success'] == true) return;
      throw ApiException('Incorrect PIN. Please try again.');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        final data = e.response?.data;
        final msg = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Incorrect PIN. Please try again.';
        throw ApiException(msg);
      }
      throw apiError(e);
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;
  bool _refreshing = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _client.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 401 from these endpoints IS the auth error itself — never refresh (loops).
    final path = err.requestOptions.path;
    final isAuthCall = path == '/auth/refresh' || path == '/auth/login';
    if (err.response?.statusCode == 401 && !_refreshing && !isAuthCall) {
      _refreshing = true;
      try {
        final refresh = await _client.refreshToken;
        if (refresh != null) {
          final res = await Dio(BaseOptions(baseUrl: ApiClient.baseUrl))
              .post('/auth/refresh', data: {'refreshToken': refresh});
          final uid = await _client.currentUserId;
          if (uid == null) {
            return handler.next(err);
          }
          await _client.saveSession(
            accessToken: res.data['accessToken'] as String,
            refreshToken: res.data['refreshToken'] as String,
            userId: uid,
          );
          // Retry the original request with the new token.
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer ${res.data['accessToken']}';
          final retry = await Dio(BaseOptions(baseUrl: ApiClient.baseUrl))
              .fetch(opts);
          return handler.resolve(retry);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await _client.clearSession();
          // Session fully expired — caller will see 401 and route to login.
        }
      } finally {
        _refreshing = false;
      }
    }
    handler.next(err);
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Extracts a friendly message from a NestJS error body.
ApiException apiError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      final msg = data['message'];
      if (msg is List) return ApiException(msg.join('\n'));
      return ApiException(msg.toString());
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException(
          'Cannot reach the server. Is the API running and USB connected?');
    }
    return ApiException('Network error: ${e.message}');
  }
  return ApiException('Unexpected error: $e');
}
