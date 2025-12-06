import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ClockApi {
  /// Clock In - clockType: 0
  static Future<Map<String, dynamic>> clockIn({
    required BuildContext context,
    required String userGuid,
    required String jobType,
    required double? latitude,
    required double? longitude,
    required String address,
    String? clientId,
    String? projectId,
    String? contractId,
    String? activityName,
    required String deviceDescription,
    required String deviceIp,
    required String deviceId,
  }) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      final clockTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = {
        "userGuid": userGuid,
        "clockTime": clockTime,
        "clockType": 0, // 0 = Clock IN
        "sourceID": 1,
        "jobType": jobType,
        "location": {"lat": latitude, "long": longitude, "name": address},
        "clientId": clientId ?? "",
        "projectGuid": projectId ?? "",
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
      };

      if (isOnline) {
        // ONLINE: Send to API
        LoggerService.info('ClockIn Request: ${Api.clock}', tag: 'ClockApi');
        LoggerService.debug(
          'ClockIn Body: ${jsonEncode(body)}',
          tag: 'ClockApi',
        );

        final response = await ApiService.post(context, Api.clock, body);

        LoggerService.info(
          'ClockIn Response: ${response.statusCode}',
          tag: 'ClockApi',
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          LoggerService.info('ClockIn Success', tag: 'ClockApi');

          // Cache clock status
          await OfflineDatabase.saveClockStatus({
            'isClockedIn': true,
            'clockLogGuid': data[0]['CLOCK_LOG_GUID'],
            'clockTime': data[0]['CLOCK_TIME'],
            'jobType': jobType,
            'address': address,
            'clientId': clientId,
            'projectId': projectId,
            'contractId': contractId,
            'activityName': activityName,
          });

          return {
            "success": true,
            "clockLogGuid": data[0]['CLOCK_LOG_GUID'],
            "clockTime": data[0]['CLOCK_TIME'],
          };
        } else {
          LoggerService.error(
            'ClockIn Failed: Status ${response.statusCode}',
            tag: 'ClockApi',
          );
          return {
            "success": false,
            "message": "Clock in failed: ${response.body}",
          };
        }
      } else {
        // OFFLINE: Queue for later sync
        final tempGuid = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        final tempClockTime = DateTime.now().toIso8601String();

        await PendingSyncService.addPendingAction(
          actionType: 'clock_in',
          payload: body,
        );

        // Save temporary clock status locally
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': true,
          'clockLogGuid': tempGuid,
          'clockTime': tempClockTime,
          'jobType': jobType,
          'address': address,
          'clientId': clientId,
          'projectId': projectId,
          'contractId': contractId,
          'activityName': activityName,
        });

        LoggerService.info(
          '📱 ClockIn queued for offline sync',
          tag: 'ClockApi',
        );

        return {
          "success": true,
          "clockLogGuid": tempGuid,
          "clockTime": tempClockTime,
          "offline": true,
        };
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'ClockIn Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );

      // On error, try to queue offline
      try {
        final tempGuid = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        final tempClockTime = DateTime.now().toIso8601String();
        final clockTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        await PendingSyncService.addPendingAction(
          actionType: 'clock_in',
          payload: {
            "userGuid": userGuid,
            "clockTime": clockTime,
            "clockType": 0,
            "sourceID": 1,
            "jobType": jobType,
            "location": {"lat": latitude, "long": longitude, "name": address},
            "clientId": clientId ?? "",
            "projectGuid": projectId ?? "",
            "contractId": contractId ?? "",
            "userAgent": {
              "description": deviceDescription,
              "publicIP": deviceIp,
              "deviceID": deviceId,
            },
            "activity": {"name": activityName ?? "", "statusFlag": "true"},
          },
        );

        return {
          "success": true,
          "clockLogGuid": tempGuid,
          "clockTime": tempClockTime,
          "offline": true,
          "message": "Saved offline due to error. Will sync when online.",
        };
      } catch (queueError) {
        LoggerService.error(
          'Failed to queue clock in',
          tag: 'ClockApi',
          error: queueError,
        );
      }

      return {"success": false, "message": "Network error: $e"};
    }
  }

  /// Clock Out - clockType: 1
  static Future<Map<String, dynamic>> clockOut({
    required BuildContext context,
    required String userGuid,
    required String jobType,
    required double? latitude,
    required double? longitude,
    required String address,
    required String clockRefGuid,
    String? clientId,
    String? projectId,
    String? contractId,
    String? activityName,
    required String deviceDescription,
    required String deviceIp,
    required String deviceId,
  }) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      final clockTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = {
        "userGuid": userGuid,
        "clockTime": clockTime,
        "clockType": 1, // 1 = Clock OUT
        "sourceID": 1,
        "jobType": jobType,
        "location": {"lat": latitude, "long": longitude, "name": address},
        "clientId": clientId ?? "",
        "projectGuid": projectId ?? "",
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
        "clockRefGuid": clockRefGuid,
      };

      if (isOnline) {
        // ONLINE: Send to API
        LoggerService.info('ClockOut Request: ${Api.clock}', tag: 'ClockApi');
        LoggerService.debug(
          'ClockOut Body: ${jsonEncode(body)}',
          tag: 'ClockApi',
        );

        final response = await ApiService.post(context, Api.clock, body);

        LoggerService.info(
          'ClockOut Response: ${response.statusCode}',
          tag: 'ClockApi',
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          LoggerService.info('ClockOut Success', tag: 'ClockApi');

          // Update clock status to clocked out
          await OfflineDatabase.saveClockStatus({
            'isClockedIn': false,
            'clockLogGuid': null,
            'clockTime': data[0]['CLOCK_TIME'],
            'jobType': null,
            'address': null,
            'clientId': null,
            'projectId': null,
            'contractId': null,
            'activityName': null,
          });

          return {"success": true, "clockTime": data[0]['CLOCK_TIME']};
        } else {
          LoggerService.error(
            'ClockOut Failed: Status ${response.statusCode}',
            tag: 'ClockApi',
          );
          return {
            "success": false,
            "message": "Clock out failed: ${response.body}",
          };
        }
      } else {
        // OFFLINE: Queue for later sync
        await PendingSyncService.addPendingAction(
          actionType: 'clock_out',
          payload: body,
        );

        // Update local clock status
        await OfflineDatabase.saveClockStatus({
          'isClockedIn': false,
          'clockLogGuid': null,
          'clockTime': DateTime.now().toIso8601String(),
          'jobType': null,
          'address': null,
          'clientId': null,
          'projectId': null,
          'contractId': null,
          'activityName': null,
        });

        LoggerService.info(
          '📱 ClockOut queued for offline sync',
          tag: 'ClockApi',
        );

        return {
          "success": true,
          "clockTime": DateTime.now().toIso8601String(),
          "offline": true,
        };
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'ClockOut Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );

      // On error, try to queue offline
      try {
        final clockTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        await PendingSyncService.addPendingAction(
          actionType: 'clock_out',
          payload: {
            "userGuid": userGuid,
            "clockTime": clockTime,
            "clockType": 1,
            "sourceID": 1,
            "jobType": jobType,
            "location": {"lat": latitude, "long": longitude, "name": address},
            "clientId": clientId ?? "",
            "projectGuid": projectId ?? "",
            "contractId": contractId ?? "",
            "userAgent": {
              "description": deviceDescription,
              "publicIP": deviceIp,
              "deviceID": deviceId,
            },
            "activity": {"name": activityName ?? "", "statusFlag": "true"},
            "clockRefGuid": clockRefGuid,
          },
        );

        return {
          "success": true,
          "clockTime": DateTime.now().toIso8601String(),
          "offline": true,
          "message": "Saved offline due to error. Will sync when online.",
        };
      } catch (queueError) {
        LoggerService.error(
          'Failed to queue clock out',
          tag: 'ClockApi',
          error: queueError,
        );
      }

      return {"success": false, "message": "Network error: $e"};
    }
  }

  /// Get latest clock status
  static Future<Map<String, dynamic>> getLatestClock(
    BuildContext context,
  ) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        LoggerService.info(
          'GetLatestClock Request: ${Api.clock_beewhere}',
          tag: 'ClockApi',
        );

        final response = await ApiService.get(context, Api.clock_beewhere);

        LoggerService.info(
          'GetLatestClock Response: ${response.statusCode}',
          tag: 'ClockApi',
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data.isEmpty) {
            LoggerService.info('No clock records found', tag: 'ClockApi');

            // Save empty status
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

            return {"success": true, "isClockedIn": false};
          }

          final latest = data[0];
          final clockType = latest['CLOCK_TYPE'];

          final result = {
            "success": true,
            "isClockedIn": clockType == 0,
            "clockLogGuid": latest['CLOCK_LOG_GUID'],
            "clockTime": latest['CLOCK_TIME'],
            "jobType": latest['JOB_TYPE'],
            "address": latest['ADDRESS'],
            "clientId": latest['CLIENT_ID'],
            "projectId": latest['PROJECT_ID'],
            "contractId": latest['CONTRACT_ID'],
            "activityName": "",
          };

          // Cache the status
          await OfflineDatabase.saveClockStatus(result);

          LoggerService.debug('Latest clock type: $clockType', tag: 'ClockApi');
          return result;
        } else {
          LoggerService.error(
            'GetLatestClock Failed: Status ${response.statusCode}',
            tag: 'ClockApi',
          );
          return {"success": false, "message": "Failed to get clock status"};
        }
      } else {
        // OFFLINE: Return cached status
        final cachedStatus = await OfflineDatabase.getClockStatus();
        if (cachedStatus != null) {
          LoggerService.info(
            '📱 Loaded clock status from offline cache',
            tag: 'ClockApi',
          );
          return cachedStatus;
        } else {
          return {"success": true, "isClockedIn": false};
        }
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'GetLatestClock Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );

      // On error, try to return cached status
      try {
        final cachedStatus = await OfflineDatabase.getClockStatus();
        if (cachedStatus != null) {
          LoggerService.info(
            '⚠️ Using cached clock status due to error',
            tag: 'ClockApi',
          );
          return cachedStatus;
        }
      } catch (cacheError) {
        LoggerService.error(
          'Failed to get cached clock status',
          tag: 'ClockApi',
          error: cacheError,
        );
      }

      return {"success": false, "message": "Network error: $e"};
    }
  }
}
