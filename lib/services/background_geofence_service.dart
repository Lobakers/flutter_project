import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
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
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
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
Future<void> startCallback() async {
  // ✨ CRITICAL: Initialize Flutter bindings first in background isolate
  WidgetsFlutterBinding.ensureInitialized();

  // ✨ FIX: Make initialization synchronous with await to prevent race conditions
  try {
    await OfflineDatabase.init();
    await PendingSyncService.init();
    LoggerService.info(
      '✅ Databases initialized in background isolate',
      tag: 'BackgroundGeofence',
    );
  } catch (e) {
    LoggerService.error(
      '❌ CRITICAL: Failed to initialize databases in background isolate',
      tag: 'BackgroundGeofence',
      error: e,
    );
    // Don't start the task handler if databases failed to initialize
    return;
  }

  FlutterForegroundTask.setTaskHandler(GeofenceTaskHandler());
}

/// Task handler that runs in the background
class GeofenceTaskHandler extends TaskHandler {
  int _violationCount = 0;
  final int _requiredViolations = GeofenceConfig.requiredViolations;
  String? _lastClockRefGuid; // ✅ Track last GUID to detect new clock-in
  DateTime?
  _clockInStartTime; // ✅ Track when clock-in started (for minimum duration protection)
  static const Duration _minimumClockInDuration = Duration(
    seconds: 30,
  ); // ✅ Don't trigger within 30s of clock-in

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
      final appInForeground = await FlutterForegroundTask.getData<bool>(
        key: 'appInForeground',
      );
      if (appInForeground == true) {
        LoggerService.debug(
          'App is in foreground, skipping background check (foreground service handles it)',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // Get clock-in state
      final state = await StorageService.getClockInState();
      if (state == null || state['isClockedIn'] != true) {
        LoggerService.debug(
          'Not clocked in, skipping geofence check',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // ✅ FIX BUG #3: Reset violation counter on new clock-in
      final currentClockRefGuid = state['clockRefGuid'] as String?;
      if (currentClockRefGuid != null &&
          currentClockRefGuid != _lastClockRefGuid) {
        LoggerService.info(
          'New clock-in detected (GUID changed), resetting violation counter and starting minimum duration timer',
          tag: 'GeofenceTaskHandler',
        );
        _violationCount = 0;
        _lastClockRefGuid = currentClockRefGuid;
        _clockInStartTime = DateTime.now(); // ✅ Reset timer on new clock-in
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

      // ✅ FIX BUG #10: Detect mock location (GPS spoofing)
      // CRITICAL SECURITY: Prevent fraudulent clock-ins via fake GPS
      if (position.isMocked) {
        LoggerService.error(
          '🚨 MOCK LOCATION DETECTED! User attempting GPS spoofing.',
          tag: 'GeofenceTaskHandler',
        );

        // Immediately auto-clock-out with special reason
        final location = '${position.latitude}, ${position.longitude}';
        await _performAutoClockOut(
          -1.0, // Distance irrelevant for mock location
          location,
          reason: 'mock_location_detected',
        );

        LoggerService.error(
          '⚠️ Auto-clocked-out due to mock location detection',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // ✅ FIX BUG #4: Check GPS accuracy before trusting the position
      // Poor GPS accuracy (e.g., indoors) can cause false violations
      if (position.accuracy > 100) {
        LoggerService.warning(
          'GPS accuracy too poor (${position.accuracy.toStringAsFixed(1)}m), skipping geofence check',
          tag: 'GeofenceTaskHandler',
        );
        // Don't increment violation counter with unreliable position
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
        'Distance from target: ${distance.toStringAsFixed(2)}m (radius: ${radiusInMeters}m, accuracy: ${position.accuracy.toStringAsFixed(1)}m)',
        tag: 'GeofenceTaskHandler',
      );

      // Check if outside radius
      if (distance > radiusInMeters) {
        // ✅ FIX: Minimum duration protection - don't trigger within 30 seconds of clock-in
        // This prevents false triggers right after clock-in when user is in transition
        if (_clockInStartTime != null) {
          final elapsed = DateTime.now().difference(_clockInStartTime!);
          if (elapsed < _minimumClockInDuration) {
            LoggerService.warning(
              'Too soon for auto clock-out (${elapsed.inSeconds}s / ${_minimumClockInDuration.inSeconds}s). Ignoring violation.',
              tag: 'GeofenceTaskHandler',
            );
            return; // Don't count this violation
          }
        }

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

          // ✨ NEW: Cross-Isolate/Cross-Engine Lock Check
          final isAlreadyProcessing = await FlutterForegroundTask.getData<bool>(
            key: 'is_currently_clocking_out',
          );
          if (isAlreadyProcessing == true) {
            LoggerService.warning(
              '⚠️ Auto clock-out already being processed globally, skipping background check.',
            );
            return;
          }

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
      final appInForeground = await FlutterForegroundTask.getData<bool>(
        key: 'appInForeground',
      );
      if (appInForeground == true) {
        LoggerService.warning(
          'App is in foreground during clock-out attempt, aborting (foreground service will handle it)',
          tag: 'GeofenceTaskHandler',
        );
        return;
      }

      // ✨ NEW: Check database to verify user is still clocked in
      // This prevents duplicate clock-out if foreground service already processed it
      try {
        final clockStatus = await OfflineDatabase.getClockStatus();
        if (clockStatus != null && clockStatus['isClockedIn'] == false) {
          LoggerService.warning(
            'User already clocked out (checked database), aborting',
            tag: 'GeofenceTaskHandler',
          );
          await FlutterForegroundTask.stopService();
          return;
        }
      } catch (e) {
        LoggerService.error(
          'Failed to check clock status from database',
          tag: 'GeofenceTaskHandler',
          error: e,
        );
        // Continue anyway - don't let database errors block auto clock-out
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

        // ✨ Database already initialized in startCallback, just use it
        try {
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
            '❌ CRITICAL: Failed to queue clock-out action',
            tag: 'GeofenceTaskHandler',
            error: e,
          );

          // ✨ Show error notification to user
          await NotificationService.showAutoClockOutNotification(
            distance: distance,
            location: location,
            reason: 'queue_failed',
          );

          // ✨ CRITICAL: Don't proceed if queue failed
          // Keep user clocked in so they can manually clock out
          await FlutterForegroundTask.stopService();
          return;
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

      // online post call
      http.Response? response;
      try {
        response = await http
            .post(
              Uri.parse('https://amscore.beesuite.app/api/clock/transaction'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'JWT $token',
              },
              body: jsonEncode(clockOutPayload),
            )
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        LoggerService.error(
          'Auto clock-out API request failed (network error)',
          tag: 'GeofenceTaskHandler',
          error: e,
        );
      }

      if (response != null && response.statusCode == 201) {
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

        // ✅ SUCCESS: Clear state and stop service
        await StorageService.clearClockInState();

        // Update offline database cache to reflect clocked-out status
        try {
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
            '✅ Updated offline database cache to clocked-out status',
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

        // Stop the service
        await FlutterForegroundTask.stopService();

        LoggerService.info(
          '🛑 Background service stopped after successful auto-clock-out',
          tag: 'GeofenceTaskHandler',
        );
      } else {
        final errorMsg = response != null
            ? 'Status: ${response.statusCode}'
            : 'Network Timeout';
        LoggerService.error(
          'Auto clock-out API failed ($errorMsg), falling back to offline queue',
          tag: 'GeofenceTaskHandler',
        );

        // ✨ CRITICAL FALLBACK: Queue it anyway so it's not lost!
        try {
          // Add a flag to payload to let sync service know this was a failed online attempt
          final fallbackPayload = Map<String, dynamic>.from(clockOutPayload);
          fallbackPayload['_isFallback'] = true;

          await PendingSyncService.addPendingAction(
            actionType: 'clock_out',
            payload: fallbackPayload,
          );

          LoggerService.info(
            '✅ Queued failed online auto-clock-out to offline queue',
            tag: 'GeofenceTaskHandler',
          );

          // Show standard notification but maybe with a hint it's pending sync
          await NotificationService.showAutoClockOutNotification(
            distance: distance,
            location: location,
            reason: reason,
          );

          // ✅ FIX BUG #2: DON'T stop service or clear state when API fails!
          // Keep monitoring so we can try again or wait for sync to succeed
          LoggerService.warning(
            '⚠️ Auto-clock-out queued but service CONTINUES monitoring (API failed)',
            tag: 'GeofenceTaskHandler',
          );
          LoggerService.warning(
            '⚠️ Service will stop when sync succeeds or next check cycle',
            tag: 'GeofenceTaskHandler',
          );

          // ❌ DON'T clear state or stop service here!
          // Exit early to keep service running
          return;
        } catch (queueError) {
          LoggerService.error(
            '❌ FAILED TO QUEUE FALLBACK ACTION: $queueError',
            tag: 'GeofenceTaskHandler',
          );

          // Last resort: Red notification
          await NotificationService.showAutoClockOutNotification(
            distance: distance,
            location: location,
            reason: 'queue_failed',
          );

          // ✅ FIX BUG #8: Clear state to prevent inconsistency
          // If we can't queue the action, clear state so user knows they need to clock in again
          LoggerService.error(
            '⚠️ Clearing clock-in state due to queue failure',
            tag: 'GeofenceTaskHandler',
          );
          await StorageService.clearClockInState();
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

          // Stop service
          await FlutterForegroundTask.stopService();
          return;
        }
      }
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
    } finally {
      // ✨ NEW: Clear the global lock after background clock-out attempt
      await FlutterForegroundTask.saveData(
        key: 'is_currently_clocking_out',
        value: false,
      );
      LoggerService.info(
        '🔓 Global native auto clock-out lock reset (BACKGROUND)',
        tag: 'GeofenceTaskHandler',
      );
    }
  }
}
