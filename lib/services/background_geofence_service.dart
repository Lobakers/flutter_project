import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/services/notification_service.dart';
import 'package:beewhere/services/storage_service.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

/// Background geofence service using foreground task
/// Maintains 15-second check interval even when app is closed
class BackgroundGeofenceService {
  static bool _isRunning = false;

  /// Start background tracking with foreground service
  static Future<void> startTracking({
    required double targetLat,
    required double targetLng,
    required String targetAddress,
    required double radiusInMeters,
    required String clockRefGuid,
  }) async {
    if (_isRunning) {
      LoggerService.warning(
        'Background tracking already running',
        tag: 'BackgroundGeofence',
      );
      return;
    }

    // Save tracking state to storage
    await StorageService.saveClockInState(
      isClockedIn: true,
      clockRefGuid: clockRefGuid,
      targetLat: targetLat,
      targetLng: targetLng,
      targetAddress: targetAddress,
      radiusInMeters: radiusInMeters,
    );

    // Initialize foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking_channel',
        channelName: 'Location Tracking',
        channelDescription: 'Monitoring your location for auto clock out',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000), // 15 seconds!
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    // Start foreground service
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Tracking Location',
        notificationText: 'Monitoring for auto clock out',
        callback: startCallback,
      );
    }

    _isRunning = true;
    LoggerService.info(
      'Background tracking started',
      tag: 'BackgroundGeofence',
    );
  }

  /// Stop background tracking
  static Future<void> stopTracking() async {
    if (!_isRunning) return;

    await FlutterForegroundTask.stopService();
    await StorageService.clearClockInState();
    _isRunning = false;

    LoggerService.info(
      'Background tracking stopped',
      tag: 'BackgroundGeofence',
    );
  }

  /// Check if tracking is running
  static bool get isRunning => _isRunning;
}

/// Callback function for foreground task
/// This runs every 15 seconds in the background
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GeofenceTaskHandler());
}

/// Task handler that runs in the background
class GeofenceTaskHandler extends TaskHandler {
  int _violationCount = 0;
  final int _requiredViolations = 2; // Same as your current implementation

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    LoggerService.info('Geofence task started', tag: 'GeofenceTaskHandler');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This runs every 15 seconds!
    _checkGeofence();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    LoggerService.info('Geofence task destroyed', tag: 'GeofenceTaskHandler');
  }

  /// Check if user is outside geofence
  Future<void> _checkGeofence() async {
    try {
      // Get tracking state from storage
      final state = await StorageService.getClockInState();

      if (state == null || state['isClockedIn'] != true) {
        LoggerService.info(
          'Not clocked in, stopping tracking',
          tag: 'GeofenceTaskHandler',
        );
        await FlutterForegroundTask.stopService();
        return;
      }

      final targetLat = state['targetLat'] as double?;
      final targetLng = state['targetLng'] as double?;
      final radiusInMeters = state['radiusInMeters'] as double?;
      final targetAddress = state['targetAddress'] as String?;

      if (targetLat == null || targetLng == null || radiusInMeters == null) {
        LoggerService.error(
          'Invalid tracking state',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Calculate distance
      final distance = GeofenceHelper.calculateDistance(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      LoggerService.debug(
        'Distance from target: ${distance.toStringAsFixed(2)}m (radius: ${radiusInMeters}m)',
        tag: 'GeofenceTaskHandler',
      );

      // Check if outside radius
      if (distance > radiusInMeters) {
        _violationCount++;
        LoggerService.warning(
          'Violation $_violationCount/$_requiredViolations: ${distance.toStringAsFixed(2)}m > ${radiusInMeters}m',
          tag: 'GeofenceTaskHandler',
        );

        // Trigger auto clock-out after required violations
        if (_violationCount >= _requiredViolations) {
          LoggerService.error(
            'User CONFIRMED OUTSIDE geofence! Distance: ${distance.toStringAsFixed(2)}m',
            tag: 'GeofenceTaskHandler',
          );

          await _performAutoClockOut(
            distance,
            targetAddress ?? 'work location',
          );
        }
      } else {
        // Back inside - reset counter
        if (_violationCount > 0) {
          LoggerService.info(
            'Back inside geofence! Resetting violation count (was $_violationCount)',
            tag: 'GeofenceTaskHandler',
          );
        }
        _violationCount = 0;
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Error checking geofence',
        tag: 'GeofenceTaskHandler',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Perform automatic clock-out
  Future<void> _performAutoClockOut(double distance, String location) async {
    try {
      LoggerService.info(
        'Starting auto clock-out process',
        tag: 'GeofenceTaskHandler',
      );

      // Get clock state
      final state = await StorageService.getClockInState();
      final clockRefGuid = state?['clockRefGuid'] as String?;

      if (clockRefGuid == null) {
        LoggerService.error(
          'No clockRefGuid found',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // Get user info from storage
      final userInfo = await StorageService.getUserInfo();
      if (userInfo == null) {
        LoggerService.error('No user info found', tag: 'GeofenceTaskHandler');
        return;
      }

      final userGuid = userInfo['userId'] as String?;
      if (userGuid == null) {
        LoggerService.error('No userId found', tag: 'GeofenceTaskHandler');
        return;
      }

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Use coordinates instead of address to save geocoding API costs
      String address =
          'Lat: ${position.latitude.toStringAsFixed(6)}, Long: ${position.longitude.toStringAsFixed(6)}';

      // Get device info
      String deviceDescription = 'Unknown Device';
      String deviceId = 'unknown';
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceDescription = '${androidInfo.brand} ${androidInfo.model}';
          deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceDescription = '${iosInfo.name} ${iosInfo.model}';
          deviceId = iosInfo.identifierForVendor ?? 'unknown';
        }
      } catch (e) {
        LoggerService.warning(
          'Failed to get device info: $e',
          tag: 'GeofenceTaskHandler',
        );
      }

      // Prepare clock out payload
      final clockOutPayload = {
        'userGuid': userGuid,
        'clockTime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'clockType': 1, // Clock OUT
        'sourceID': 1,
        'jobType': state?['jobType'] ?? 'Office',
        'location': {
          'lat': position.latitude,
          'long': position.longitude,
          'name': address,
        },
        'clientId': state?['clientId'] ?? '',
        'projectGuid': state?['projectId'] ?? '',
        'contractId': state?['contractId'] ?? '',
        'userAgent': {
          'description': deviceDescription,
          'publicIP': '0.0.0.0',
          'deviceID': deviceId,
        },
        'activity': {'name': '', 'statusFlag': 'true'},
        'clockRefGuid': clockRefGuid,
      };

      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (!isOnline) {
        // OFFLINE: Queue for later sync
        LoggerService.info(
          '📱 Auto clock-out queued (offline)',
          tag: 'GeofenceTaskHandler',
        );

        await PendingSyncService.addPendingAction(
          actionType: 'clock_out',
          payload: clockOutPayload,
        );

        // Show notification
        await NotificationService.showAutoClockOutNotification(
          distance: distance,
          location: location,
        );

        // Clear clock-in state
        await StorageService.clearClockInState();

        // Stop tracking
        await FlutterForegroundTask.stopService();

        LoggerService.info(
          '✅ Auto clock-out queued successfully (will sync when online)',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // ONLINE: Call clock-out API directly
      LoggerService.info('Calling clock-out API', tag: 'GeofenceTaskHandler');

      final token = await StorageService.getToken();
      if (token == null) {
        LoggerService.error('No auth token found', tag: 'GeofenceTaskHandler');
        return;
      }

      final response = await http.post(
        Uri.parse('https://devamscore.beesuite.app/api/clock/transaction'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode(clockOutPayload),
      );

      if (response.statusCode == 201) {
        LoggerService.info(
          'Auto clock-out API success',
          tag: 'GeofenceTaskHandler',
        );

        // Show notification
        await NotificationService.showAutoClockOutNotification(
          distance: distance,
          location: location,
        );
      } else {
        LoggerService.error(
          'Auto clock-out API failed: ${response.statusCode}',
          tag: 'GeofenceTaskHandler',
        );
      }

      // Clear clock-in state
      await StorageService.clearClockInState();

      // Wait a bit to ensure notification is posted
      await Future.delayed(const Duration(seconds: 2));

      // Stop tracking
      await FlutterForegroundTask.stopService();

      LoggerService.info(
        'Auto clock-out completed',
        tag: 'GeofenceTaskHandler',
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Error performing auto clock-out',
        tag: 'GeofenceTaskHandler',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
