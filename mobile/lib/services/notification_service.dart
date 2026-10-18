import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../main.dart';
import 'api_service.dart';

/// Top-level background message handler - must be a free function (not a method).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('[FCM Background] Firebase initialized in background isolate');
    }
  } catch (e) {
    debugPrint('[FCM Background] Firebase init error: $e');
  }
  debugPrint('[FCM Background] Message received: ${message.messageId}');
  debugPrint('[FCM Background] Data: ${message.data}');
  debugPrint('[FCM Background] Notification title: ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseMessaging.instance;
      }
    } catch (_) {}
    return null;
  }

  static const String visitorChannelId = 'visitor_requests';
  static const String visitorChannelName = 'Visitor Requests';
  static const String visitorChannelDesc =
      'Real-time alerts and approvals for gate visitors';

  bool _initialized = false;
  GlobalKey<NavigatorState>? navigatorKey;
  ApiService? _authenticatedApi;
  StreamSubscription<String>? _tokenRefreshSubscription;
  Map<String, dynamic>? _pendingNotificationData;

  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    if (_initialized) return;
    navigatorKey = navKey;

    debugPrint('════════════════════════════════════════════════');
    debugPrint('[NotificationService] Starting initialization...');

    // Step 1: Local Notifications + Android channel
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[NotificationService] Local notification tapped. Payload: ${response.payload}');
          if (response.payload != null && response.payload!.isNotEmpty) {
            _handleNotificationPayload(response.payload!);
          }
        },
      );
      debugPrint('[NotificationService] Flutter local notifications initialized');

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 500]);
        final channel = AndroidNotificationChannel(
          visitorChannelId,
          visitorChannelName,
          description: visitorChannelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: vibrationPattern,
          showBadge: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );
        await androidPlugin.createNotificationChannel(channel);
        debugPrint('[NotificationService] Android channel "$visitorChannelId" created (importance: MAX)');

        try {
          final granted = await androidPlugin.requestNotificationsPermission();
          debugPrint('[NotificationService] Notification permission result: $granted');
        } catch (e) {
          debugPrint('[NotificationService] Notification permission request: $e');
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Local notifications setup error: $e');
    }

    // Step 2: Firebase Core initialization
    bool firebaseReady = false;
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[NotificationService] Initializing Firebase with DefaultFirebaseOptions...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('[NotificationService] Firebase.initializeApp() succeeded');
      } else {
        debugPrint('[NotificationService] Firebase already initialized (${Firebase.apps.length} app(s))');
      }
      firebaseReady = Firebase.apps.isNotEmpty;
    } catch (e) {
      debugPrint('[NotificationService] Firebase.initializeApp() FAILED: $e');
    }

    // Step 3: Firebase Messaging setup
    if (firebaseReady && _fcm != null) {
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        debugPrint('[NotificationService] Background message handler registered');
      } catch (e) {
        debugPrint('[NotificationService] Background handler error: $e');
      }

      // Register one refresh listener for the lifetime of the service. It
      // reads the current authenticated API client, so account switches never
      // post a token using a stale user's session.
      _tokenRefreshSubscription ??= _fcm!.onTokenRefresh.listen((newToken) async {
        final api = _authenticatedApi;
        if (api?.token == null) return;
        try {
          await api!.post('device-tokens', {
            'fcm_token': newToken,
            'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          });
        } catch (e) {
          debugPrint('[FCM Token Refresh] Registration failed: $e');
        }
      });

      try {
        final settings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        debugPrint('[NotificationService] FCM Permission: ${settings.authorizationStatus}');
        debugPrint('[NotificationService]   alert=${settings.alert}, badge=${settings.badge}, sound=${settings.sound}');
      } catch (e) {
        debugPrint('[NotificationService] FCM requestPermission error: $e');
      }

      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('======== FCM FOREGROUND MESSAGE ========');
          debugPrint('[FCM Foreground] ID: ${message.messageId}');
          debugPrint('[FCM Foreground] Title: ${message.notification?.title}');
          debugPrint('[FCM Foreground] Body:  ${message.notification?.body}');
          debugPrint('[FCM Foreground] Data:  ${message.data}');
          debugPrint('========================================');
          _showForegroundNotification(message);
        });
        debugPrint('[NotificationService] Foreground message listener attached');
      } catch (e) {
        debugPrint('[NotificationService] Foreground listener error: $e');
      }

      try {
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('======== FCM NOTIFICATION OPENED ========');
          debugPrint('[FCM Opened] ID: ${message.messageId}');
          debugPrint('[FCM Opened] Data: ${message.data}');
          debugPrint('=========================================');
          _handleRemoteMessageData(message.data);
        });
        debugPrint('[NotificationService] onMessageOpenedApp listener attached');
      } catch (e) {
        debugPrint('[NotificationService] onMessageOpenedApp error: $e');
      }

      try {
        final initialMessage = await _fcm!.getInitialMessage();
        if (initialMessage != null) {
          debugPrint('======== FCM LAUNCH FROM NOTIFICATION ========');
          debugPrint('[FCM Launch] App launched via notification tap');
          debugPrint('[FCM Launch] Data: ${initialMessage.data}');
          debugPrint('==============================================');
          _handleRemoteMessageData(initialMessage.data);
        } else {
          debugPrint('[NotificationService] Normal launch (no pending FCM message)');
        }
      } catch (e) {
        debugPrint('[NotificationService] getInitialMessage error: $e');
      }
    } else {
      debugPrint('[NotificationService] Firebase not ready - FCM listeners skipped');
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialization complete');
    debugPrint('════════════════════════════════════════════════');
  }

  /// Called after login or session restore - gets FCM token and registers with Laravel.
  Future<void> registerDeviceToken(ApiService api, {String? userId, String? userEmail}) async {
    // Never associate a device with an absent or stale auth session.
    if (api.token == null || userId == null) return;
    _authenticatedApi = api;

    try {
      final fcm = _fcm;
      if (fcm == null) {
        debugPrint('[FCM Token] FAILED - FirebaseMessaging not available (Firebase not initialized)');
        debugPrint('========================================');
        return;
      }

      final settings = await fcm.getNotificationSettings();
      final isGranted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      debugPrint('[FCM Token] Permission: ${settings.authorizationStatus} (granted: $isGranted)');

      if (!isGranted) {
        debugPrint('[FCM Token] WARNING: Notification permission NOT granted');
      }

      final token = await fcm.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FCM Token] FAILED - FCM token is null/empty');
        debugPrint('========================================');
        return;
      }
      try {
        await api.post('device-tokens', {
          'fcm_token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        });
        debugPrint('[FCM Token] Token successfully registered with Laravel backend');
      } catch (e) {
        debugPrint('[FCM Token] FAILED to register token with Laravel: $e');
      }

      debugPrint('[FCM Token] Device token registered with backend');
    } catch (e) {
      debugPrint('[FCM Token] registerDeviceToken error: $e');
    }

    debugPrint('========================================');
  }

  /// Remove device token on logout.
  Future<void> unregisterDeviceToken(ApiService api) async {
    debugPrint('[FCM Token] Unregistering device token on logout...');
    if (identical(_authenticatedApi, api)) _authenticatedApi = null;
    try {
      final fcm = _fcm;
      if (fcm != null) {
        final token = await fcm.getToken();
        if (token != null && token.isNotEmpty) {
          final encoded = Uri.encodeComponent(token);
          await api.delete('device-tokens?fcm_token=$encoded');
          debugPrint('[FCM Token] Token unregistered from Laravel');
        }
      }
    } catch (e) {
      debugPrint('[FCM Token] Unregister error: $e');
    } finally {
      if (identical(_authenticatedApi, api)) _authenticatedApi = null;
    }
  }

  /// Dispatch a notification tap captured before Flutter had an authenticated
  /// route mounted (for example, a terminated app launch).
  void handlePendingNotification() {
    final data = _pendingNotificationData;
    if (data == null || navigatorKey?.currentContext == null) return;
    _pendingNotificationData = null;
    _handleRemoteMessageData(data);
  }

  /// Displays a heads-up notification when the app is in the foreground.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      final data = message.data;

      final title = notification?.title ?? data['title'] ?? 'Visitor Request';
      final body = notification?.body ??
          data['body'] ??
          (data['visitor_name'] != null
              ? '${data['visitor_name']} is requesting entry to Flat ${data['flat_number'] ?? ''} (${data['building'] ?? ''}).'
              : 'A new visitor request is waiting for your approval.');

      debugPrint('[FCM Foreground] Showing notification: "$title"');

      final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 500]);
      final androidDetails = AndroidNotificationDetails(
        visitorChannelId,
        visitorChannelName,
        channelDescription: visitorChannelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibrationPattern,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(body),
        icon: '@mipmap/ic_launcher',
      );

      final details = NotificationDetails(android: androidDetails);
      final rawId = data['visitor_id'] ?? data['visitor_request_id'] ??
          DateTime.now().millisecondsSinceEpoch;
      final notificationId =
          int.tryParse(rawId.toString()) ?? (DateTime.now().millisecondsSinceEpoch % 100000);

      await _localNotifications.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode(data),
      );
      debugPrint('[FCM Foreground] Local notification shown (id: $notificationId)');
    } catch (e) {
      debugPrint('[FCM Foreground] Error showing local notification: $e');
    }
  }

  void _handleNotificationPayload(String rawPayload) {
    try {
      final data = jsonDecode(rawPayload);
      if (data is Map) {
        _handleRemoteMessageData(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('[NotificationService] Payload parse error: $e');
    }
  }

  /// Routes a notification data payload to the correct UI handler.
  ///
  /// Uses [data]['type'] (set by FCM) or [data]['notification_type'] to
  /// determine what to show. Falls back to legacy visitor_id behaviour so
  /// existing notifications without an explicit type still work.
  void _handleRemoteMessageData(Map<String, dynamic> data) {
    final type = data['type']?.toString()
        ?? data['notification_type']?.toString()
        ?? '';
    final visitorId = data['visitor_id']?.toString()
        ?? data['visitor_request_id']?.toString();

    debugPrint('[NotificationService] Handling type: "$type", visitor_id: $visitorId');

    // Notification taps can arrive on the login screen or during session
    // restoration. Keep only the structured payload until a valid session is
    // registered; never expose visitor details or controls while logged out.
    if (_authenticatedApi?.token == null) {
      _pendingNotificationData = Map<String, dynamic>.from(data);
      debugPrint('[NotificationService] Queued notification tap until authentication completes');
      return;
    }

    final context = navigatorKey?.currentContext;
    if (context == null) {
      _pendingNotificationData = Map<String, dynamic>.from(data);
      debugPrint('[NotificationService] Queued notification tap until navigation is ready');
      return;
    }

    switch (type) {
      // ── Resident receives a new visitor approval request ────────────────
      case 'visitor_request':
      case 'visitor_approval_request':
        if (visitorId != null) {
          debugPrint('[NotificationService] Opening Visitor Approval Sheet for visitor #$visitorId');
          showVisitorApprovalSheet(context, data);
        }
        break;

      // ── Security guard receives result of their visitor request ─────────
      // ── Resident receives check-in / check-out alert ────────────────────
      case 'visitor_approved':
      case 'visitor_rejected':
      case 'visitor_checked_in':
      case 'visitor_checked_out':
        showSocietyNotificationSheet(context, data);
        break;

      default:
        // Legacy: if there is a visitor_id and no explicit type, assume
        // it is an approval-request notification (older app version compat).
        if (visitorId != null) {
          debugPrint('[NotificationService] Legacy fallback: showing approval sheet for visitor #$visitorId');
          showVisitorApprovalSheet(context, data);
        } else {
          debugPrint('[NotificationService] No handler for type: "$type" — notification visible in bell');
        }
        break;
    }
  }
}
