import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  String? token;
  Future<void> Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path) => _request('GET', path);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body);
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _request('PUT', path, body);
  Future<Map<String, dynamic>> delete(String path) => _request('DELETE', path);

  Future<Uint8List> getBytes(String path) async {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final response = await _client.get(Uri.parse('$base/$normalized'), headers: {
      'Accept': '*/*',
      if (token != null) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    if (response.statusCode == 401) await onUnauthorized?.call();
    throw ApiException('Evidence could not be loaded (${response.statusCode}).',
        statusCode: response.statusCode);
  }

  Future<Map<String, dynamic>> postMultipart(
      String path, Map<String, String> fields, Map<String, String> filePaths,
      {String fileField = 'evidence[]'}) async {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final request = http.MultipartRequest('POST', Uri.parse('$base/$normalized'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      })
      ..fields.addAll(fields);
    for (final entry in filePaths.entries) {
      request.files.add(await http.MultipartFile.fromPath(
          entry.key.isEmpty ? fileField : entry.key, entry.value));
    }
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    if (response.statusCode == 401) await onUnauthorized?.call();
    final errors = decoded['errors'];
    final detail = errors is Map && errors.isNotEmpty
        ? (errors.values.first as List).first.toString()
        : decoded['message']?.toString();
    throw ApiException(detail ?? 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode);
  }

  /// Performs a test health check call to verify connectivity to Laravel backend.
  Future<bool> testHealthCheck() async {
    if (!ApiConfig.isValid) {
      debugPrint('❌ [CONNECTIVITY TEST FAILED] ApiConfig is not configured.');
      return false;
    }
    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final healthUrl = '$normalizedBase/health';
    debugPrint('==================================================');
    debugPrint('🔍 [CONNECTIVITY TEST] Starting API Health Check');
    debugPrint('🔍 [CONNECTIVITY TEST] Environment: ${ApiConfig.environmentName}');
    debugPrint('🔍 [CONNECTIVITY TEST] Device     : ${ApiConfig.devicePlatform}');
    debugPrint('🔍 [CONNECTIVITY TEST] Target URL : $healthUrl');
    try {
      final response = await _client
          .get(Uri.parse(healthUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      debugPrint('✅ [CONNECTIVITY TEST SUCCESS]');
      debugPrint('   STATUS CODE: ${response.statusCode}');
      debugPrint('   RESPONSE BODY: ${response.body}');
      debugPrint('==================================================');
      return response.statusCode == 200;
    } catch (e, stack) {
      debugPrint('❌ [CONNECTIVITY TEST FAILED]');
      debugPrint('   ERROR TYPE: ${e.runtimeType}');
      debugPrint('   ERROR MESSAGE: $e');
      debugPrint('   STACK TRACE: $stack');
      debugPrint('==================================================');
      return false;
    }
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    if (!ApiConfig.isValid) {
      debugPrint('🚨 [API CONFIG ERROR] Request attempted with invalid or missing API URL.');
      debugPrint('👉 ${ApiConfig.configurationError}');
      throw ApiException(ApiConfig.shortConfigurationError);
    }

    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$normalizedBase/$normalizedPath');
    final isLogin = path == 'auth/login';

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    if (kDebugMode) {
      final sanitizedHeaders = Map<String, String>.from(requestHeaders);
      if (sanitizedHeaders.containsKey('Authorization')) {
        sanitizedHeaders['Authorization'] = 'Bearer ***';
      }

      debugPrint('---------------- API REQUEST ----------------');
      debugPrint('API ENVIRONMENT: ${ApiConfig.environmentName}');
      debugPrint('TARGET DEVICE  : ${ApiConfig.devicePlatform}');
      debugPrint('REQUEST URL    : $uri');
      debugPrint('HTTP METHOD    : $method');
      debugPrint('REQUEST HEADERS: $sanitizedHeaders');
      if (body != null) {
        final sanitized = Map<String, dynamic>.from(body);
        if (sanitized.containsKey('password')) sanitized['password'] = '***';
        if (sanitized.containsKey('fcm_token')) sanitized['fcm_token'] = '***';
        if (sanitized.containsKey('device_token')) sanitized['device_token'] = '***';
        if (sanitized.containsKey('token') && !isLogin) sanitized['token'] = '***';
        debugPrint('PAYLOAD: ${jsonEncode(sanitized)}');
      }
    }

    final request = http.Request(method, uri)
      ..headers.addAll(requestHeaders)
      ..body = body == null ? '' : jsonEncode(body);

    try {
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);

      if (kDebugMode) {
        debugPrint('STATUS CODE: ${response.statusCode}');
        if (isLogin) {
          debugPrint('RESPONSE: Received login response with status ${response.statusCode}');
        } else {
          final preview = response.body.length > 300
              ? '${response.body.substring(0, 300)}...'
              : response.body;
          debugPrint('RESPONSE BODY: $preview');
        }
        debugPrint('---------------------------------------------');
      }

      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      if (response.statusCode == 401) {
        await onUnauthorized?.call();
      }

      final errors = decoded['errors'];
      final detail = errors is Map && errors.isNotEmpty
          ? (errors.values.first as List).first.toString()
          : decoded['message']?.toString();

      final defaultMessage = switch (response.statusCode) {
        401 => 'The provided credentials are incorrect.',
        403 => 'Access denied. You do not have permission for this action.',
        404 => 'The requested resource was not found.',
        422 => 'The provided credentials are incorrect.',
        >= 500 => 'Server error. Please try again later.',
        _ => 'Request failed with status ${response.statusCode}.',
      };

      throw ApiException(detail ?? defaultMessage,
          statusCode: response.statusCode);
    } on TimeoutException catch (e, stack) {
      debugPrint('🚨 [API TIMEOUT] Request to $uri timed out after 15s ($e)');
      debugPrint('   API Environment: ${ApiConfig.environmentName}');
      debugPrint('   Target Device  : ${ApiConfig.devicePlatform}');
      debugPrint('   Stack trace    : $stack');
      throw ApiException(
        'Unable to connect to Nivora server (${uri.host}).\n'
        'Connection timed out. Please verify that the server is running and your phone and PC are on the same network.',
      );
    } on SocketException catch (e, stack) {
      final host = uri.host;
      debugPrint('🚨 [API SOCKET ERROR] Failed connecting to $uri (OS Error: ${e.osError?.message}, Code: ${e.osError?.errorCode}, Host: $host, Port: ${uri.port})');
      debugPrint('   API Environment: ${ApiConfig.environmentName}');
      debugPrint('   Target Device  : ${ApiConfig.devicePlatform}');
      debugPrint('   Stack trace    : $stack');
      if (host == '127.0.0.1' || host == 'localhost') {
        debugPrint('👉 Tip: On a physical Android device, 127.0.0.1 refers to the phone itself, not the PC.');
        debugPrint('👉 If using USB cable: ensure "adb reverse tcp:8000 tcp:8000" was run.');
        debugPrint('👉 If using Wi-Fi: launch the app using START_ANDROID_LAN.bat.');
        throw const ApiException(
          'Cannot connect to Nivora server at 127.0.0.1.\n\n'
          '• If using a USB cable: verify "adb reverse tcp:8000 tcp:8000" is active.\n'
          '• If using Wi-Fi: launch the app using START_ANDROID_LAN.bat.',
        );
      }
      if (e.osError?.errorCode == 11001 || e.message.contains('Failed host lookup') || e.message.contains('No address associated')) {
        throw ApiException(
          'Cannot resolve server host "$host".\n'
          'Please verify the IP/domain or launch using START_ANDROID_LAN.bat.',
        );
      }
      throw ApiException(
        'Cannot connect to Nivora server ($host:${uri.port}).\n'
        'Please check that Laravel is running on port ${uri.port} and your phone and PC are on the same Wi-Fi network.',
      );
    } on http.ClientException catch (e, stack) {
      debugPrint('🚨 [API CLIENT ERROR] ClientException ($e, URI: $uri)');
      debugPrint('   Stack trace: $stack');
      throw const ApiException(
        'Cannot connect to Nivora server. Please check that the server is running and verify your network connection.',
      );
    } on IOException catch (e, stack) {
      debugPrint('🚨 [API I/O ERROR] IOException ($e, URI: $uri)');
      debugPrint('   Stack trace: $stack');
      throw ApiException('Network I/O error while connecting to ${uri.host}.');
    } on FormatException catch (e, stack) {
      debugPrint('🚨 [API FORMAT ERROR] Failed to parse server response as JSON ($e)');
      debugPrint('   Stack trace: $stack');
      throw const ApiException(
        'The backend returned an invalid response. Please contact support.',
      );
    } catch (e, stack) {
      debugPrint('🚨 [API UNEXPECTED ERROR] ${e.runtimeType} ($e, URI: $uri)');
      debugPrint('   Stack trace: $stack');
      if (e is ApiException) rethrow;
      throw const ApiException('Unable to connect to server. Please try again.');
    }
  }
}

