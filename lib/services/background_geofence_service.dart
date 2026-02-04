import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/config/geofence_config.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/services/notification_service.dart';
import 'package:beewhere/services/storage_service.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

/// Background geofence service using foreground task
/// Check interval configured in GeofenceConfig.backgroundCheckInterval
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
    // ✨ FIX: Always stop existing service first to ensure clean restart
    // This prevents multiple services from running simultaneously
    try {
      if (await FlutterForegroundTask.isRunningService) {
        LoggerService.warning(
          'Background service already running, stopping for clean restart',
          tag: 'BackgroundGeofence',
        );
        await FlutterForegroundTask.stopService();
        // Wait for service to fully stop
        await Future.delayed(const Duration(milliseconds: 800));
      }
    } catch (e) {
      LoggerService.warning(
        'Error checking/stopping existing service: $e',
        tag: 'BackgroundGeofence',
      );
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
        eventAction: ForegroundTaskEventAction.repeat(
          GeofenceConfig.backgroundCheckInterval.inMilliseconds,
        ),
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
  // ✨ Initialize OfflineDatabase in background isolate
  OfflineDatabase.init().then((_) {
    LoggerService.info(
      'OfflineDatabase initialized in background isolate',
      tag: 'BackgroundGeofence',
    );
  }).catchError((e) {
    LoggerService.error(
      'Failed to initialize OfflineDatabase in background isolate',
      tag: 'BackgroundGeofence',
      error: e,
    );
  });
  
  FlutterForegroundTask.setTaskHandler(GeofenceTaskHandler());
}

/// Task handler that runs in the background
class GeofenceTaskHandler extends TaskHandler {
  int _violationCount = 0;
  final int _requiredViolations = GeofenceConfig.requiredViolations;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    LoggerService.info('Geofence task started', tag: 'GeofenceTaskHandler');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This runs at the interval configured in GeofenceConfig.backgroundCheckInterval
    _checkGeofence();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    LoggerService.info('Geofence task destroyed', tag: 'GeofenceTaskHandler');
  }

  /// Check if user is outside geofence
  Future<void> _checkGeofence() async {
    try {
      // ✨ Check if app is in foreground - if so, skip background check
      // The foreground service (AutoClockOutService) will handle it
      final appInForeground = await FlutterForegroundTask.getData<bool>(key: 'appInForeground');
      if (appInForeground == true) {
        LoggerService.debug(
          'App is in foreground, skipping background check (foreground service handles it)',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

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

      // ✨ Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        LoggerService.error(
          'Location service DISABLED! Triggering auto clock-out',
          tag: 'GeofenceTaskHandler',
        );

        await _performAutoClockOut(
          -1.0, // Special value to indicate location disabled
          targetAddress ?? 'work location',
          reason: 'location_disabled',
        );
        return;
      }

      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        // If we can't get location, check if service is disabled
        final stillEnabled = await Geolocator.isLocationServiceEnabled();
        if (!stillEnabled) {
          LoggerService.error(
            'Location service disabled (detected via error)',
            tag: 'GeofenceTaskHandler',
          );

          await _performAutoClockOut(
            -1.0,
            targetAddress ?? 'work location',
            reason: 'location_disabled',
          );
        } else {
          LoggerService.error(
            'Failed to get location: $e',
            tag: 'GeofenceTaskHandler',
          );
        }
        return;
      }

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
  Future<void> _performAutoClockOut(
    double distance,
    String location, {
    String? reason,
  }) async {
    try {
      LoggerService.info(
        'Starting auto clock-out process (BACKGROUND)',
        tag: 'GeofenceTaskHandler',
      );

      // ✨ DOUBLE-CHECK: Is app in foreground? If so, abort (foreground service handles it)
      final appInForeground = await FlutterForegroundTask.getData<bool>(key: 'appInForeground');
      if (appInForeground == true) {
        LoggerService.warning(
          'App is in foreground during clock-out attempt, aborting (foreground service will handle it)',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // Get clock state
      final state = await StorageService.getClockInState();
      final clockRefGuid = state?['clockRefGuid'] as String?;

      if (clockRefGuid == null) {
        LoggerService.error(
          'No clockRefGuid found, user may have already clocked out',
          tag: 'GeofenceTaskHandler',
        );
        // Stop tracking since there's no active clock-in
        await FlutterForegroundTask.stopService();
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

        // ✨ CRITICAL: Ensure PendingSyncService is initialized in background isolate
        // The background isolate has its own database connection
        try {
          await PendingSyncService.init();
          LoggerService.info(
            '✅ PendingSyncService initialized in background isolate',
            tag: 'GeofenceTaskHandler',
          );
          
          await PendingSyncService.addPendingAction(
            actionType: 'clock_out',
            payload: clockOutPayload,
          );
          
          // Verify it was added
          final pendingCount = await PendingSyncService.getPendingCount();
          LoggerService.info(
            '✅ Clock-out action queued. Total pending actions: $pendingCount',
            tag: 'GeofenceTaskHandler',
          );
          
          // List all pending actions for debugging
          final allActions = await PendingSyncService.getPendingActions();
          LoggerService.debug(
            '📋 All pending actions: ${allActions.map((a) => a['action_type']).join(', ')}',
            tag: 'GeofenceTaskHandler',
          );
        } catch (e) {
          LoggerService.error(
            'Failed to queue clock-out action',
            tag: 'GeofenceTaskHandler',
            error: e,
          );
        }

        // Show notification
        await NotificationService.showAutoClockOutNotification(
          distance: distance,
          location: location,
          reason: reason,
        );

        // Clear clock-in state
        await StorageService.clearClockInState();

        // ✨ CRITICAL: Update OfflineDatabase to clocked-out status
        // This prevents foreground service from restarting monitoring when app reopens
        try {
          // Ensure OfflineDatabase is initialized before updating
          await OfflineDatabase.init();
          
          await OfflineDatabase.saveClockStatus({
            'isClockedIn': false,
            'clockLogGuid': null,
            'clockTime': null,
            'jobType': null,
            'address': null,
            'clientId': null,
            'projectId': null,
            'contractId': null,
            'activityName': null,
          });
          
          LoggerService.info(
            '✅ Updated OfflineDatabase to clocked-out status (OFFLINE)',
            tag: 'GeofenceTaskHandler',
          );
        } catch (e) {
          LoggerService.error(
            'Failed to update OfflineDatabase: $e',
            tag: 'GeofenceTaskHandler',
            error: e,
          );
        }

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
        Uri.parse('https://amscore.beesuite.app/api/clock/transaction'),
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
          reason: reason,
        );
      } else {
        LoggerService.error(
          'Auto clock-out API failed: ${response.statusCode}',
          tag: 'GeofenceTaskHandler',
        );
      }

      // Clear clock-in state
      await StorageService.clearClockInState();

      // ✨ FIX: Update offline database cache to reflect clocked-out status
      // This ensures UI updates correctly when app resumes
      try {
        // Ensure OfflineDatabase is initialized before updating
        await OfflineDatabase.init();
        
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': false,
          'clockLogGuid': null,
          'clockTime': null,
          'jobType': null,
          'address': null,
          'clientId': null,
          'projectId': null,
          'contractId': null,
          'activityName': null,
        });
        
        LoggerService.info(
          '✅ Updated offline database cache to clocked-out status (ONLINE)',
          tag: 'GeofenceTaskHandler',
        );
      } catch (e) {
        LoggerService.error(
          'Failed to update offline database: $e',
          tag: 'GeofenceTaskHandler',
          error: e,
        );
      }

      // Wait a bit to ensure notification is posted
      await Future.delayed(const Duration(seconds: 2));

      // Stop tracking
      await FlutterForegroundTask.stopService();

      LoggerService.info(
        'Auto clock-out completed (BACKGROUND)',
        tag: 'GeofenceTaskHandler',
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Error performing auto clock-out',
        tag: 'GeofenceTaskHandler',
        error: e,
        stackTrace: stackTrace,
      );
      
      // Ensure service stops even on error
      try {
        await FlutterForegroundTask.stopService();
      } catch (stopError) {
        LoggerService.error(
          'Failed to stop service after error',
          tag: 'GeofenceTaskHandler',
          error: stopError,
        );
      }
    }
  }
}
