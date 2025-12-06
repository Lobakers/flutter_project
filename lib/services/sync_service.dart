import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:flutter/material.dart';

/// Service to sync pending offline actions
class SyncService {
  static bool _isSyncing = false;
  static int _syncedCount = 0;
  static int _failedCount = 0;

  /// Check if currently syncing
  static bool get isSyncing => _isSyncing;

  /// Get last sync stats
  static Map<String, int> get lastSyncStats => {
    'synced': _syncedCount,
    'failed': _failedCount,
  };

  /// Initialize sync service - register with connectivity service
  static void init() {
    ConnectivityService.registerSyncCallback(() {
      syncPendingActions(null); // No context needed for background sync
    });
    LoggerService.info('✅ SyncService initialized', tag: 'SyncService');
  }

  /// Manually trigger sync (with context for UI feedback)
  static Future<Map<String, dynamic>> syncPendingActions(
    BuildContext? context,
  ) async {
    if (_isSyncing) {
      LoggerService.info('⚠️ Sync already in progress', tag: 'SyncService');
      return {'success': false, 'message': 'Sync already in progress'};
    }

    if (!ConnectivityService.isOnline) {
      LoggerService.info('⚠️ Cannot sync: offline', tag: 'SyncService');
      return {'success': false, 'message': 'No internet connection'};
    }

    _isSyncing = true;
    _syncedCount = 0;
    _failedCount = 0;

    try {
      LoggerService.info('🔄 Starting sync...', tag: 'SyncService');

      final pendingActions = await PendingSyncService.getPendingActions();
      LoggerService.info(
        '📋 Found ${pendingActions.length} pending actions',
        tag: 'SyncService',
      );

      if (pendingActions.isEmpty) {
        _isSyncing = false;
        return {'success': true, 'message': 'No pending actions to sync'};
      }

      // Process each pending action
      for (var action in pendingActions) {
        final actionType = action['action_type'];
        final payload = action['payload'];
        final actionId = action['id'];

        LoggerService.info(
          '🔄 Syncing action: $actionType (ID: $actionId)',
          tag: 'SyncService',
        );

        try {
          bool success = false;

          // Route to appropriate API based on action type
          switch (actionType) {
            case 'clock_in':
              success = await _syncClockIn(context, payload);
              break;
            case 'clock_out':
              success = await _syncClockOut(context, payload);
              break;
            case 'update_activity':
              success = await _syncUpdateActivity(context, payload);
              break;
            case 'edit_time_request':
              // TODO: Implement when needed
              LoggerService.info(
                '⚠️ edit_time_request sync not yet implemented',
                tag: 'SyncService',
              );
              break;
            default:
              LoggerService.error(
                'Unknown action type: $actionType',
                tag: 'SyncService',
              );
          }

          if (success) {
            // Remove from queue
            await PendingSyncService.removePendingAction(actionId);
            _syncedCount++;
            LoggerService.info('✅ Synced action $actionId', tag: 'SyncService');
          } else {
            // Increment retry count
            await PendingSyncService.incrementRetry(actionId, 'Sync failed');
            _failedCount++;
            LoggerService.error(
              '❌ Failed to sync action $actionId',
              tag: 'SyncService',
            );
          }
        } catch (e) {
          await PendingSyncService.incrementRetry(actionId, e.toString());
          _failedCount++;
          LoggerService.error(
            'Error syncing action $actionId',
            tag: 'SyncService',
            error: e,
          );
        }
      }

      _isSyncing = false;

      LoggerService.info(
        '✅ Sync complete: $_syncedCount synced, $_failedCount failed',
        tag: 'SyncService',
      );

      return {'success': true, 'synced': _syncedCount, 'failed': _failedCount};
    } catch (e) {
      _isSyncing = false;
      LoggerService.error('Sync error', tag: 'SyncService', error: e);
      return {'success': false, 'message': 'Sync error: $e'};
    }
  }

  /// Sync clock in action
  static Future<bool> _syncClockIn(
    BuildContext? context,
    Map<String, dynamic> payload,
  ) async {
    try {
      // If no context, we can't make API calls that require it
      if (context == null) {
        LoggerService.info(
          '⚠️ No context for clock in sync, will retry later',
          tag: 'SyncService',
        );
        return false;
      }

      // Extract payload data
      final userGuid = payload['userGuid'];
      final jobType = payload['jobType'];
      final location = payload['location'];
      final clientId = payload['clientId'];
      final projectGuid = payload['projectGuid'];
      final contractId = payload['contractId'];
      final userAgent = payload['userAgent'];
      final activity = payload['activity'];

      // Call the API directly (bypass offline check)
      final body = {
        "userGuid": userGuid,
        "clockTime": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "clockType": 0,
        "sourceID": 1,
        "jobType": jobType,
        "location": location,
        "clientId": clientId ?? "",
        "projectGuid": projectGuid ?? "",
        "contractId": contractId ?? "",
        "userAgent": userAgent,
        "activity": activity,
      };

      final response = await ApiService.post(context, '/api/clock', body);

      return response.statusCode == 201;
    } catch (e) {
      LoggerService.error(
        'Error syncing clock in',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Sync clock out action
  static Future<bool> _syncClockOut(
    BuildContext? context,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (context == null) {
        LoggerService.info(
          '⚠️ No context for clock out sync, will retry later',
          tag: 'SyncService',
        );
        return false;
      }

      // Call the API directly
      final body = {
        "userGuid": payload['userGuid'],
        "clockTime": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "clockType": 1,
        "sourceID": 1,
        "jobType": payload['jobType'],
        "location": payload['location'],
        "clientId": payload['clientId'] ?? "",
        "projectGuid": payload['projectGuid'] ?? "",
        "contractId": payload['contractId'] ?? "",
        "userAgent": payload['userAgent'],
        "activity": payload['activity'],
        "clockRefGuid": payload['clockRefGuid'],
      };

      final response = await ApiService.post(context, '/api/clock', body);

      return response.statusCode == 201;
    } catch (e) {
      LoggerService.error(
        'Error syncing clock out',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Sync update activity action
  static Future<bool> _syncUpdateActivity(
    BuildContext? context,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (context == null) {
        LoggerService.info(
          '⚠️ No context for activity update sync, will retry later',
          tag: 'SyncService',
        );
        return false;
      }

      final clockLogGuid = payload['clockLogGuid'];
      final activities = payload['activity'] as List<dynamic>;

      // Convert to proper format
      final activitiesList = activities
          .map((a) => a as Map<String, dynamic>)
          .toList();

      // Call the API directly
      final body = {'clockLogGuid': clockLogGuid, 'activity': activitiesList};

      final response = await ApiService.patch(
        context,
        '/api/clock/activity',
        body,
      );

      return response.statusCode == 200;
    } catch (e) {
      LoggerService.error(
        'Error syncing activity update',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }
}
