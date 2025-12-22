import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for showing local push notifications
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  /// Initialize notification service
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      print('🔔 [NotificationService] Initializing...');

      // Android initialization settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization settings
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      // Combined initialization settings
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize
      final bool? initialized = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      print('🔔 [NotificationService] Initialization result: $initialized');

      // Create notification channel for Android
      await _createNotificationChannel();

      _isInitialized = true;
      print('🔔 [NotificationService] Initialized successfully');
    } catch (e) {
      print('🔔 ❌ [NotificationService] Initialization failed: $e');
    }
  }

  /// Create Android notification channel
  static Future<void> _createNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'auto_clockout_channel', // id
        'Auto Clock Out', // name
        description: 'Notifications for automatic clock out events',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      print('🔔 [NotificationService] Channel created');
    } catch (e) {
      print('🔔 ❌ [NotificationService] Channel creation failed: $e');
    }
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    // When user taps notification, app will open
    // You can add custom navigation logic here if needed
    print('Notification tapped: ${response.payload}');
  }

  /// Request notification permissions
  static Future<bool> requestPermissions() async {
    try {
      if (await Permission.notification.isGranted) {
        return true;
      }

      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      print('🔔 ❌ [NotificationService] Permission request failed: $e');
      return false;
    }
  }

  /// Show auto clock-out notification
  static Future<void> showAutoClockOutNotification({
    required double distance,
    required String location,
    String? reason,
  }) async {
    print(
      '🔔 [NotificationService] Attempting to show auto clock-out notification',
    );
    if (!_isInitialized) {
      await init();
    }

    try {
      // Determine notification message based on reason
      String message;
      if (reason == 'location_disabled') {
        message = 'Location service was disabled. You have been automatically clocked out.';
      } else {
        message = 'You moved ${distance.toStringAsFixed(0)}m from $location. You are being automatically clocked out.';
      }

      final AndroidNotificationDetails
      androidDetails = AndroidNotificationDetails(
        'auto_clockout_channel',
        'Auto Clock Out',
        channelDescription: 'Notifications for automatic clock out events',
        importance: Importance.max, // Changed to max
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF4B39EF),
        styleInformation: BigTextStyleInformation(message),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999, // Changed ID to avoid conflicts
        'Auto Clock Out',
        'You are being automatically clocked out.',
        details,
        payload: 'auto_clockout',
      );
      print('🔔 [NotificationService] Notification shown successfully');
    } catch (e) {
      print('🔔 ❌ [NotificationService] Failed to show notification: $e');
    }
  }

  /// Show foreground service notification (persistent while tracking)
  static Future<void> showTrackingNotification() async {
    if (!_isInitialized) {
      await init();
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'tracking_channel',
          'Location Tracking',
          channelDescription: 'Ongoing location tracking for auto clock out',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      1, // notification id
      'Tracking Location',
      'Monitoring your location for auto clock out',
      details,
      payload: 'tracking',
    );
  }

  /// Cancel tracking notification
  static Future<void> cancelTrackingNotification() async {
    await _notifications.cancel(1);
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
