import 'dart:convert';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/storage_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:http/http.dart' as http;

/// Service to sync pending offline actions
/// Works without BuildContext by using direct HTTP calls
class SyncService {
  static bool _isSyncing = false;
  static int _syncedCount = 0;
  static int _failedCount = 0;
  static const String _baseUrl = 'https://devamscore.beesuite.app';

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
      syncPendingActions(); // Auto-sync when connection restored
    });
    LoggerService.info('✅ SyncService initialized', tag: 'SyncService');
  }

  /// Sync all pending actions (works without context)
  static Future<Map<String, dynamic>> syncPendingActions() async {
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

      // Get auth token
      final token = await StorageService.getToken();
      if (token == null) {
        LoggerService.error('No auth token found', tag: 'SyncService');
        _isSyncing = false;
        return {'success': false, 'message': 'No auth token'};
      }

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
        final payload =
            action['payload'] as Map<String, dynamic>; // Already decoded
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
              final result = await _syncClockIn(token, payload);
              success = result['success'] == true;

              // ✨ If clock-in succeeded, update local cache and pending clock-outs
              if (success && result['realGuid'] != null) {
                final realGuid = result['realGuid'];

                // Update any pending clock-out actions that reference temp GUID
                await _updatePendingClockOutReferences(
                  pendingActions: pendingActions,
                  realGuid: realGuid,
                );
              }
              break;
            case 'clock_out':
              success = await _syncClockOut(token, payload);
              break;
            case 'update_activity':
              success = await _syncUpdateActivity(token, payload);
              break;
            case 'submit_time_request':
              success = await _syncSubmitTimeRequest(token, payload);
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

  /// Sync clock in action using direct HTTP call
  /// Returns Map with 'success' and optionally 'realGuid' and 'clockTime'
  static Future<Map<String, dynamic>> _syncClockIn(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      LoggerService.debug(
        'Syncing clock in: ${jsonEncode(payload)}',
        tag: 'SyncService',
      );

      final response = await http.post(
        Uri.parse('$_baseUrl/api/clock/transaction'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode({
          "userGuid": payload['userGuid'],
          "clockTime": DateTime.now().millisecondsSinceEpoch ~/ 1000,
          "clockType": 0,
          "sourceID": 1,
          "jobType": payload['jobType'],
          "location": payload['location'],
          "clientId": payload['clientId'] ?? "",
          "projectGuid": payload['projectGuid'] ?? "",
          "contractId": payload['contractId'] ?? "",
          "userAgent": payload['userAgent'],
          "activity": payload['activity'],
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final realGuid = data[0]['CLOCK_LOG_GUID'];
        final clockTime = data[0]['CLOCK_TIME'];

        LoggerService.info(
          '✅ Clock in synced successfully. Real GUID: $realGuid',
          tag: 'SyncService',
        );

        // Return the real GUID so we can update local cache
        return {'success': true, 'realGuid': realGuid, 'clockTime': clockTime};
      } else {
        LoggerService.error(
          'Clock in sync failed: ${response.statusCode} - ${response.body}',
          tag: 'SyncService',
        );
        return {'success': false};
      }
    } catch (e) {
      LoggerService.error(
        'Error syncing clock in',
        tag: 'SyncService',
        error: e,
      );
      return {'success': false};
    }
  }

  /// Sync clock out action using direct HTTP call
  static Future<bool> _syncClockOut(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      LoggerService.debug(
        'Syncing clock out: ${jsonEncode(payload)}',
        tag: 'SyncService',
      );

      final response = await http.post(
        Uri.parse('$_baseUrl/api/clock/transaction'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode({
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
        }),
      );

      if (response.statusCode == 201) {
        LoggerService.info(
          '✅ Clock out synced successfully',
          tag: 'SyncService',
        );
        return true;
      } else {
        LoggerService.error(
          'Clock out sync failed: ${response.statusCode} - ${response.body}',
          tag: 'SyncService',
        );
        return false;
      }
    } catch (e) {
      LoggerService.error(
        'Error syncing clock out',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Sync update activity action using direct HTTP call
  static Future<bool> _syncUpdateActivity(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      LoggerService.debug(
        'Syncing activity update: ${jsonEncode(payload)}',
        tag: 'SyncService',
      );

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/clock/activity'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode({
          'clockLogGuid': payload['clockLogGuid'],
          'activity': payload['activity'],
        }),
      );

      if (response.statusCode == 200) {
        LoggerService.info(
          '✅ Activity update synced successfully',
          tag: 'SyncService',
        );
        return true;
      } else {
        LoggerService.error(
          'Activity update sync failed: ${response.statusCode} - ${response.body}',
          tag: 'SyncService',
        );
        return false;
      }
    } catch (e) {
      LoggerService.error(
        'Error syncing activity update',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Sync submit time request action using direct HTTP call
  static Future<bool> _syncSubmitTimeRequest(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      LoggerService.debug(
        'Syncing time request: ${jsonEncode(payload)}',
        tag: 'SyncService',
      );

      final response = await http.post(
        Uri.parse('$_baseUrl/support'), // Correct URL (no /api)
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        LoggerService.info(
          '✅ Time request synced successfully',
          tag: 'SyncService',
        );
        return true;
      } else {
        LoggerService.error(
          'Time request sync failed: ${response.statusCode} - ${response.body}',
          tag: 'SyncService',
        );
        return false;
      }
    } catch (e) {
      LoggerService.error(
        'Error syncing time request',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Update pending actions (any type) to use real GUID instead of temp GUID
  /// This scans all pending actions and replaces references
  static Future<void> _updatePendingClockOutReferences({
    required List<Map<String, dynamic>> pendingActions,
    required String realGuid,
  }) async {
    try {
      for (var action in pendingActions) {
        bool updated = false;
        final payload =
            action['payload'] as Map<String, dynamic>; // Already decoded
        final actionType = action['action_type'];

        // 1. Check clockRefGuid (used in clock_out)
        if (payload.containsKey('clockRefGuid')) {
          final ref = payload['clockRefGuid'];
          if (ref != null && ref.toString().startsWith('temp_')) {
            payload['clockRefGuid'] = realGuid;
            updated = true;
          }
        }

        // 2. Check clockLogGuid (used in update_activity)
        if (payload.containsKey('clockLogGuid')) {
          final ref = payload['clockLogGuid'];
          if (ref != null && ref.toString().startsWith('temp_')) {
            payload['clockLogGuid'] = realGuid;
            updated = true;
          }
        }

        if (updated) {
          LoggerService.info(
            '🔄 Updated $actionType reference to real GUID: $realGuid',
            tag: 'SyncService',
          );
          await PendingSyncService.updatePendingAction(
            actionId: action['id'],
            payload: payload,
          );
        }
      }
    } catch (e) {
      LoggerService.error(
        'Error updating pending references',
        tag: 'SyncService',
        error: e,
      );
    }
  }
}
