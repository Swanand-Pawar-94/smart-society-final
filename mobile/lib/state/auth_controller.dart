import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class AuthController extends ChangeNotifier {

  AuthController(this._api) {
    _api.onUnauthorized = _clearExpiredSession;
  }
  final ApiService _api;
  ApiService get api => _api;
  final _storage = const FlutterSecureStorage();
  Session? session;
  bool loading = true;
  String? error;
  String? message;

  Future<void> restore() async {
    // Perform startup health check connectivity test
    await _api.testHealthCheck();
    final token = await _storage.read(key: 'auth_token');
    if (token != null) {
      _api.token = token;
      try {
        final json = await _api.get('auth/me');
        session = Session(
            token: token,
            user: AppUser.fromJson(
                (json['data'] ?? json['user']) as Map<String, dynamic>));
        // Register push notification device token
        NotificationService.instance.registerDeviceToken(
          _api,
          userId: session?.user.id.toString(),
          userEmail: session?.user.email,
        );
      } on ApiException {
        await _storage.delete(key: 'auth_token');
        _api.token = null;
      }
    }
    loading = false;
    notifyListeners();
  }


  Future<void> _clearExpiredSession() async {
    await _storage.delete(key: 'auth_token');
    _api.token = null;
    session = null;
    notifyListeners();
  }

  void clearError() {
    if (error != null) {
      error = null;
      notifyListeners();
    }
  }

  Future<bool> login(
    String login,
    String password, {
    String? requestedRole,
    bool rememberMe = true,
  }) async {
    error = null;
    message = null;
    notifyListeners();
    try {
      final json = await _api.post('auth/login', {
        'login': login,
        'password': password,
        'device_name': 'smart-society-mobile',
        if (requestedRole != null) 'requested_role': requestedRole,
      });
      session = Session.fromLoginJson(json['data'] as Map<String, dynamic>);
      _api.token = session!.token;
      if (rememberMe) {
        await _storage.write(key: 'auth_token', value: session!.token);
      } else {
        await _storage.delete(key: 'auth_token');
      }
      // Register FCM device token
      NotificationService.instance.registerDeviceToken(
        _api,
        userId: session?.user.id.toString(),
        userEmail: session?.user.email,
      );
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(Map<String, dynamic> payload) async {
    error = null;
    message = null;
    notifyListeners();
    try {
      final json = await _api.post('auth/register', payload);
      message = json['message']?.toString() ?? 'Registration completed.';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    error = null;
    message = null;
    notifyListeners();
    try {
      final json = await _api.post('auth/forgot-password', {'email': email});
      message = json['message']?.toString() ?? 'Password-reset request sent.';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    // Unregister device token
    await NotificationService.instance.unregisterDeviceToken(_api);
    try {
      await _api.post('auth/logout', {});
    } on ApiException {
      // Local credentials must still be cleared when the server is unavailable.
    }
    await _storage.delete(key: 'auth_token');
    _api.token = null;
    session = null;
    message = null;
    error = null;
    notifyListeners();
  }

}
