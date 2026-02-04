import 'dart:convert';
import 'dart:io';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/storage_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart'; // For basename function

/// Service to sync pending offline actions
/// Works without BuildContext by using direct HTTP calls
class SyncService {
  static bool _isSyncing = false;
  static int _syncedCount = 0;
  static int _failedCount = 0;
  // Production API (currently active)
  static const String _baseUrl = 'https://amscore.beesuite.app';
  
  // Development API (commented out for testing later)
  // static const String _baseUrl = 'https://devamscore.beesuite.app';

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

      // Track last clock-in timestamp to prevent timestamp collisions
      int? lastClockInTime;

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

              // ✨ Track clock-in timestamp
              if (success && payload['clockTime'] != null) {
                lastClockInTime = payload['clockTime'] as int;
              }

              // ✨ If clock-in succeeded, update local cache and pending clock-outs
              if (success && result['realGuid'] != null) {
                final realGuid = result['realGuid'];

                // Update any pending clock-out actions that reference temp GUID
                await _updatePendingClockOutReferences(
                  pendingActions: pendingActions,
                  realGuid: realGuid,
                );

                // ✨ CRITICAL FIX: Update StorageService clock-in state with real GUID
                // This ensures background service uses the real GUID if it triggers auto clock-out
                try {
                  final clockInState = await StorageService.getClockInState();
                  if (clockInState != null && clockInState['isClockedIn'] == true) {
                    // Check if the stored GUID is a temp GUID
                    final storedGuid = clockInState['clockRefGuid'] as String?;
                    if (storedGuid != null && storedGuid.startsWith('temp_')) {
                      LoggerService.info(
                        '🔄 Updating StorageService with real GUID: $realGuid (was: $storedGuid)',
                        tag: 'SyncService',
                      );
                      
                      await StorageService.saveClockInState(
                        isClockedIn: true,
                        clockRefGuid: realGuid, // ✨ Update with real GUID
                        targetLat: clockInState['targetLat'] as double?,
                        targetLng: clockInState['targetLng'] as double?,
                        targetAddress: clockInState['targetAddress'] as String?,
                        radiusInMeters: clockInState['radiusInMeters'] as double?,
                        jobType: clockInState['jobType'] as String?,
                        clientId: clockInState['clientId'] as String?,
                        projectId: clockInState['projectId'] as String?,
                        contractId: clockInState['contractId'] as String?,
                      );
                    }
                  }
                } catch (e) {
                  LoggerService.error(
                    'Failed to update StorageService with real GUID',
                    tag: 'SyncService',
                    error: e,
                  );
                }
                
                // ✨ ALSO UPDATE OfflineDatabase cache with real GUID
                // This ensures UI shows correct GUID after sync
                try {
                  final cachedStatus = await OfflineDatabase.getClockStatus();
                  if (cachedStatus != null && cachedStatus['isClockedIn'] == true) {
                    final cachedGuid = cachedStatus['clockLogGuid'] as String?;
                    if (cachedGuid != null && cachedGuid.startsWith('temp_')) {
                      LoggerService.info(
                        '🔄 Updating OfflineDatabase with real GUID: $realGuid (was: $cachedGuid)',
                        tag: 'SyncService',
                      );
                      
                      await OfflineDatabase.saveClockStatus({
                        'isClockedIn': true,
                        'clockLogGuid': realGuid, // ✨ Update with real GUID
                        'clockTime': result['clockTime'], // Use real clock time from API
                        'jobType': cachedStatus['jobType'],
                        'address': cachedStatus['address'],
                        'clientId': cachedStatus['clientId'],
                        'projectId': cachedStatus['projectId'],
                        'contractId': cachedStatus['contractId'],
                        'activityName': cachedStatus['activityName'],
                      });
                    }
                  }
                } catch (e) {
                  LoggerService.error(
                    'Failed to update OfflineDatabase with real GUID',
                    tag: 'SyncService',
                    error: e,
                  );
                }
                
                // ✨ FIX: Add small delay to ensure clock-in is fully committed to database
                // before clock-out starts. This prevents race condition where clock-out
                // gets inserted before clock-in due to parallel API calls.
                await Future.delayed(const Duration(milliseconds: 500));
                LoggerService.debug(
                  '⏱️ Waited 500ms after clock-in to ensure database commit',
                  tag: 'SyncService',
                );
              }
              break;
            case 'clock_out':
              // ✨ FIX: Ensure clock-out timestamp is at least 1 second after clock-in
              if (lastClockInTime != null && payload['clockTime'] != null) {
                final clockOutTime = payload['clockTime'] as int;
                if (clockOutTime <= lastClockInTime) {
                  LoggerService.warning(
                    '⚠️ Clock-out timestamp ($clockOutTime) is same or earlier than clock-in ($lastClockInTime). Adding 1 second.',
                    tag: 'SyncService',
                  );
                  payload['clockTime'] = lastClockInTime + 1;
                }
              }
              success = await _syncClockOut(token, payload);
              break;
            case 'update_activity':
              success = await _syncUpdateActivity(token, payload);
              break;
            case 'submit_time_request':
              success = await _syncSubmitTimeRequest(token, payload);
              break;
            case 'support_request':
              success = await _syncSupportRequest(token, payload);
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
      final clockTime = payload['clockTime'];
      LoggerService.info(
        '🔄 Syncing CLOCK IN with clockTime: $clockTime (${DateTime.fromMillisecondsSinceEpoch(clockTime * 1000)})',
        tag: 'SyncService',
      );
      LoggerService.debug(
        'Full payload: ${jsonEncode(payload)}',
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
          "clockTime": clockTime, // ✨ FIX: Use original offline timestamp
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
      final clockTime = payload['clockTime'];
      LoggerService.info(
        '🔄 Syncing CLOCK OUT with clockTime: $clockTime (${DateTime.fromMillisecondsSinceEpoch(clockTime * 1000)}), clockRefGuid: ${payload['clockRefGuid']}',
        tag: 'SyncService',
      );
      LoggerService.debug(
        'Full payload: ${jsonEncode(payload)}',
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
          "clockTime": clockTime, // ✨ FIX: Use original offline timestamp
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
        // ✨ Check if this is an orphaned clock-out (referencing non-existent GUID)
        final responseBody = response.body.toLowerCase();
        if (response.statusCode == 400 && 
            (responseBody.contains('fail to create resource') || 
             responseBody.contains('resource'))) {
          LoggerService.warning(
            '⚠️ Clock-out references non-existent GUID (orphaned record). This will be removed from queue.',
            tag: 'SyncService',
          );
          // Return true to remove it from queue (it's an orphaned record that can't be synced)
          return true;
        }
        
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

  /// Sync support request action using direct HTTP call
  /// Handles file upload if cached file path is present
  static Future<bool> _syncSupportRequest(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      LoggerService.debug(
        'Syncing support request: ${jsonEncode(payload)}',
        tag: 'SyncService',
      );

      // Check if there's a cached file that needs to be uploaded first
      final cachedFilePath = payload['_cachedFilePath'] as String?;
      String? actualFilename = payload['supportingDoc'];

      if (cachedFilePath != null && cachedFilePath.isNotEmpty) {
        LoggerService.info(
          'Support request has cached file, uploading first: $cachedFilePath',
          tag: 'SyncService',
        );

        // Upload the file first
        final fileUploadResult = await _uploadFileToAzure(
          token,
          cachedFilePath,
        );

        if (fileUploadResult['success']) {
          actualFilename = fileUploadResult['filename'];
          LoggerService.info(
            'File uploaded successfully: $actualFilename',
            tag: 'SyncService',
          );
        } else {
          LoggerService.error(
            'File upload failed during support request sync',
            tag: 'SyncService',
          );
          return false;
        }
      }

      // Prepare payload without internal fields
      final cleanPayload = Map<String, dynamic>.from(payload);
      cleanPayload.remove('_cachedFilePath');
      cleanPayload['supportingDoc'] = actualFilename ?? '';

      // Submit support request
      final response = await http.post(
        Uri.parse('$_baseUrl/support'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'JWT $token',
        },
        body: jsonEncode(cleanPayload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        LoggerService.info(
          '✅ Support request synced successfully',
          tag: 'SyncService',
        );
        return true;
      } else {
        LoggerService.error(
          'Support request sync failed: ${response.statusCode} - ${response.body}',
          tag: 'SyncService',
        );
        return false;
      }
    } catch (e) {
      LoggerService.error(
        'Error syncing support request',
        tag: 'SyncService',
        error: e,
      );
      return false;
    }
  }

  /// Helper: Upload file to Azure storage
  static Future<Map<String, dynamic>> _uploadFileToAzure(
    String token,
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {'success': false, 'message': 'File not found'};
      }

      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      final uri = Uri.parse('$_baseUrl/api/azure/upload');

      final request = http.MultipartRequest("POST", uri);
      request.headers['Authorization'] = 'JWT $token';

      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: basename(filePath),
      );

      request.files.add(multipartFile);

      final response = await request.send();
      final responseString = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseString);
        return {"success": true, "filename": jsonResponse['filename']};
      } else {
        // Generate fallback filename if upload fails (matching support_api behavior)
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final originalFilename = basename(filePath);
        final generatedFilename = '${timestamp}_$originalFilename';

        LoggerService.info(
          'File upload returned ${response.statusCode}, using generated filename: $generatedFilename',
          tag: 'SyncService',
        );

        return {
          "success": true,
          "filename": generatedFilename,
          "note": "File upload endpoint not available. Filename generated.",
        };
      }
    } catch (e) {
      LoggerService.error(
        'Error uploading file during sync',
        tag: 'SyncService',
        error: e,
      );
      return {'success': false, 'message': 'Upload error: $e'};
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
