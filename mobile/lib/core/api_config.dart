import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Available API environments supported by Smart Society
enum ApiEnvironment {
  /// Local LAN Wi-Fi connection (PC active LAN IP, e.g. http://192.168.1.9:8000/api)
  lan,

  /// Physical Android device tethered via USB with ADB reverse (http://127.0.0.1:8000/api)
  usb,

  /// Android Emulator mapping host machine (http://10.0.2.2:8000/api)
  emulator,

  /// Production Hostinger / cloud deployment (HTTPS)
  production,

  /// Automated widget / unit test environment
  test,

  /// Custom endpoint passed via --dart-define
  custom,

  /// No valid URL configured
  unconfigured,
}

/// Centralized API Configuration for Smart Society.
///
/// This is the SINGLE SOURCE OF TRUTH for backend API networking.
/// Never hardcode IP addresses or URLs elsewhere in the codebase.
///
/// THREE PRIMARY ENVIRONMENTS ARE SUPPORTED:
///
/// A. PHYSICAL ANDROID PHONE OVER WI-FI / LAN:
///    Launch with: START_ANDROID_LAN.bat
///    Or command:  flutter run --dart-define=API_BASE_URL=http://<PC_IP>:8000/api
///
/// B. PHYSICAL ANDROID PHONE VIA USB (ADB REVERSE):
///    Launch with: START_ANDROID_USB.bat
///    Or command:  adb reverse tcp:8000 tcp:8000
///                 flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api --dart-define=API_ENV=usb
///
/// C. ANDROID EMULATOR:
///    Launch with: START_ANDROID_EMULATOR.bat
///    Or command:  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api --dart-define=API_ENV=emulator
///
/// D. PRODUCTION BUILD (Smart Society Cloud):
///    Command:     flutter build apk --release --dart-define=API_ENV=production --dart-define=API_BASE_URL=https://smartsociety.codevizor.com/api
class ApiConfig {
  const ApiConfig._();

  // ─── Environment Constants ──────────────────────────────────────────────────

  /// Live production API Base URL deployed on the Smart Society cloud backend.
  /// Overrideable at build time via: --dart-define=API_BASE_URL=https://smartsociety.codevizor.com/api
  static const String productionBaseUrl = 'https://smartsociety.codevizor.com/api';

  /// Android Emulator loopback URL (10.0.2.2 maps to host 127.0.0.1 in standard Android emulator)
  static const String emulatorBaseUrl = 'http://10.0.2.2:8000/api';

  /// ADB Reverse URL for physical device connected via USB (requires: adb reverse tcp:8000 tcp:8000)
  static const String usbBaseUrl = 'http://127.0.0.1:8000/api';

  // ─── Compile-Time Defines ───────────────────────────────────────────────────

  /// URL explicitly supplied via `--dart-define=API_BASE_URL=...`
  static const String _rawBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Environment mode explicitly supplied via `--dart-define=API_ENV=...`
  /// Supported values: 'lan', 'usb', 'emulator', 'production'
  static const String _rawEnv = String.fromEnvironment('API_ENV');

  // ─── Test Detection ─────────────────────────────────────────────────────────

  /// Returns true when executing in a `flutter test` runner environment.
  static bool get isTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  // ─── Runtime Base URL Resolution ────────────────────────────────────────────

  /// The active runtime API base URL.
  ///
  /// Guaranteed behavior:
  /// - If explicitly passed via `--dart-define=API_BASE_URL=...`, that URL is used.
  /// - If `--dart-define=API_ENV=...` is specified ('emulator', 'usb', 'production'), that preset is used.
  /// - In release builds (`kReleaseMode`), defaults to [productionBaseUrl].
  /// - In unit/widget tests, defaults to [usbBaseUrl] to satisfy mocked requests.
  /// - On desktop platforms (Windows, macOS, Linux), defaults to [usbBaseUrl] (127.0.0.1 is local PC).
  /// - On physical Android/iOS devices without a define: DOES NOT silently fall back to 127.0.0.1.
  ///   Returns empty string, triggering clear configuration diagnostics.
  static String get baseUrl {
    if (_rawBaseUrl.isNotEmpty) {
      return _rawBaseUrl.trim();
    }

    switch (_rawEnv.toLowerCase().trim()) {
      case 'emulator':
        return emulatorBaseUrl;
      case 'usb':
        return usbBaseUrl;
      case 'production':
      case 'prod':
        return productionBaseUrl;
      default:
        break;
    }

    if (kReleaseMode) {
      return productionBaseUrl;
    }

    if (isTest) {
      return usbBaseUrl;
    }

    if (!kIsWeb) {
      try {
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          return usbBaseUrl;
        }
      } catch (_) {}
    }

    // Unconfigured on physical mobile device: return empty to prevent silent localhost failure
    return '';
  }

  /// Whether a valid, usable API base URL is configured.
  static bool get isValid {
    final url = baseUrl;
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // ─── Diagnostics & Metadata ─────────────────────────────────────────────────

  /// Current resolved environment
  static ApiEnvironment get environment {
    if (isTest) return ApiEnvironment.test;
    final url = baseUrl;
    if (url.isEmpty) return ApiEnvironment.unconfigured;

    if (_rawEnv.isNotEmpty) {
      switch (_rawEnv.toLowerCase().trim()) {
        case 'emulator':
          return ApiEnvironment.emulator;
        case 'usb':
          return ApiEnvironment.usb;
        case 'lan':
        case 'local':
          return ApiEnvironment.lan;
        case 'production':
        case 'prod':
          return ApiEnvironment.production;
      }
    }

    if (url.startsWith('https://')) return ApiEnvironment.production;
    if (url.contains('10.0.2.2')) return ApiEnvironment.emulator;
    if (url.contains('127.0.0.1') || url.contains('localhost')) {
      return ApiEnvironment.usb;
    }
    return ApiEnvironment.lan;
  }

  /// Human-friendly description of the active environment
  static String get environmentName => switch (environment) {
    ApiEnvironment.lan => 'Local LAN (Physical Phone via Wi-Fi)',
    ApiEnvironment.usb => 'USB Cable (ADB Reverse)',
    ApiEnvironment.emulator => 'Android Emulator',
    ApiEnvironment.production => 'Production (HTTPS)',
    ApiEnvironment.test => 'Automated Test',
    ApiEnvironment.custom => 'Custom Endpoint',
    ApiEnvironment.unconfigured => 'Unconfigured (Missing API_BASE_URL)',
  };

  /// Current target device / platform description
  static String get devicePlatform {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) {
        if (environment == ApiEnvironment.emulator) {
          return 'Android Emulator';
        }
        return 'Android Physical Device';
      }
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isWindows) return 'Windows Desktop';
      if (Platform.isMacOS) return 'macOS Desktop';
      if (Platform.isLinux) return 'Linux Desktop';
    } catch (_) {}
    return 'Unknown Device';
  }

  /// Clear, actionable configuration error message when unconfigured
  static String get configurationError {
    if (isValid) return '';
    return 'Backend API URL is not configured.\n\n'
        'Please launch the app using one of the helper scripts:\n'
        '  • START_ANDROID_LAN.bat   (Physical phone over Wi-Fi)\n'
        '  • START_ANDROID_USB.bat   (Physical phone via USB cable)\n'
        '  • START_ANDROID_EMULATOR.bat (Android Emulator)\n\n'
        'Or pass: --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8000/api';
  }

  /// Compact single-line error message for UI banners
  static String get shortConfigurationError {
    if (isValid) return '';
    return 'Backend API URL is not configured. Please launch via START_ANDROID_LAN.bat or pass --dart-define=API_BASE_URL=...';
  }

  /// Logs startup diagnostics to the console (debug builds only)
  static void printStartupDiagnostics() {
    final envLabel = switch (environment) {
      ApiEnvironment.lan => 'local',
      ApiEnvironment.usb => 'usb',
      ApiEnvironment.emulator => 'emulator',
      ApiEnvironment.production => 'production',
      ApiEnvironment.test => 'test',
      _ => 'local',
    };
    debugPrint('API Environment: $envLabel');
    debugPrint('API Base URL: ${baseUrl.isEmpty ? "[NOT CONFIGURED]" : baseUrl}');

    debugPrint('╔════════════════════════════════════════════════════════════════╗');
    debugPrint('║                SMART SOCIETY — API DIAGNOSTICS                 ║');
    debugPrint('╠════════════════════════════════════════════════════════════════╣');
    debugPrint('║ API Environment : ${environmentName.padRight(45)}║');
    debugPrint('║ API Base URL    : ${(baseUrl.isEmpty ? "[NOT CONFIGURED]" : baseUrl).padRight(45)}║');
    debugPrint('║ Target Device   : ${devicePlatform.padRight(45)}║');
    debugPrint('║ Build Mode      : ${(kReleaseMode ? "Release" : kDebugMode ? "Debug" : "Profile").padRight(45)}║');
    debugPrint('║ Status          : ${(isValid ? "READY" : "CONFIG ERROR (Missing API_BASE_URL)").padRight(45)}║');
    debugPrint('╚════════════════════════════════════════════════════════════════╝');
    if (!isValid) {
      debugPrint('🚨 [CONFIG ERROR] No API_BASE_URL was configured for this run.');
      debugPrint('👉 For physical phone over Wi-Fi: Run mobile\\START_ANDROID_LAN.bat');
      debugPrint('👉 For physical phone via USB:   Run mobile\\START_ANDROID_USB.bat');
      debugPrint('👉 For Android Emulator:         Run mobile\\START_ANDROID_EMULATOR.bat');
    }
  }

  static bool get isDevelopment => baseUrl.startsWith('http://');
  static bool get isProduction => baseUrl.startsWith('https://');
}




