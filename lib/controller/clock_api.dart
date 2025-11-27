import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/logger_service.dart';
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
      final body = {
        "userGuid": userGuid,
        "clockTime": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "clockType": 0, // 0 = Clock IN
        "sourceID": 1,
        "jobType": jobType,
        "location": {"lat": latitude, "long": longitude, "name": address},
        "clientId": clientId ?? "",
        "projectGuid": projectId ?? "", // 👈 FIXED: was "projectId"
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
      };

      LoggerService.info('ClockIn Request: ${Api.clock}', tag: 'ClockApi');
      LoggerService.debug('ClockIn Body: ${jsonEncode(body)}', tag: 'ClockApi');

      final response = await ApiService.post(context, Api.clock, body);

      LoggerService.info(
        'ClockIn Response: ${response.statusCode}',
        tag: 'ClockApi',
      );
      LoggerService.debug(
        'ClockIn Response Body: ${response.body}',
        tag: 'ClockApi',
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        LoggerService.info('ClockIn Success', tag: 'ClockApi');

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
    } catch (e, stackTrace) {
      LoggerService.error(
        'ClockIn Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );
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
      final body = {
        "userGuid": userGuid,
        "clockTime": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "clockType": 1, // 1 = Clock OUT
        "sourceID": 1,
        "jobType": jobType,
        "location": {"lat": latitude, "long": longitude, "name": address},
        "clientId": clientId ?? "",
        "projectGuid": projectId ?? "", // 👈 FIXED: was "projectId"
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
        "clockRefGuid": clockRefGuid,
      };

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
      LoggerService.debug(
        'ClockOut Response Body: ${response.body}',
        tag: 'ClockApi',
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        LoggerService.info('ClockOut Success', tag: 'ClockApi');

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
    } catch (e, stackTrace) {
      LoggerService.error(
        'ClockOut Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );
      return {"success": false, "message": "Network error: $e"};
    }
  }

  /// Get latest clock status
  static Future<Map<String, dynamic>> getLatestClock(
    BuildContext context,
  ) async {
    try {
      LoggerService.info(
        'GetLatestClock Request: ${Api.clock_beewhere}',
        tag: 'ClockApi',
      );

      final response = await ApiService.get(context, Api.clock_beewhere);

      LoggerService.info(
        'GetLatestClock Response: ${response.statusCode}',
        tag: 'ClockApi',
      );
      LoggerService.debug(
        'GetLatestClock Response Body: ${response.body}',
        tag: 'ClockApi',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        LoggerService.debug(
          'Parsed data type: ${data.runtimeType}',
          tag: 'ClockApi',
        );

        if (data.isEmpty) {
          LoggerService.info('No clock records found', tag: 'ClockApi');
          return {"success": true, "isClockedIn": false};
        }

        LoggerService.debug(
          'Data is list: ${data is List}, length: ${data is List ? data.length : 'N/A'}',
          tag: 'ClockApi',
        );

        final latest = data[0];
        final clockType = latest['CLOCK_TYPE'];
        LoggerService.debug('Latest clock type: $clockType', tag: 'ClockApi');

        return {
          "success": true,
          "isClockedIn": clockType == 0,
          "clockLogGuid": latest['CLOCK_LOG_GUID'],
          "clockTime": latest['CLOCK_TIME'],
          "jobType": latest['JOB_TYPE'],
          "address": latest['ADDRESS'],
          "clientId": latest['CLIENT_ID'],
          "projectId": latest['PROJECT_ID'], // 👈 Not PROJECT_GUID
          "contractId": latest['CONTRACT_ID'],
          "activityName": "", // 👈 FIXED: ACTIVITY is XML string, not object
        };
      } else {
        LoggerService.error(
          'GetLatestClock Failed: Status ${response.statusCode}',
          tag: 'ClockApi',
        );
        return {"success": false, "message": "Failed to get clock status"};
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'GetLatestClock Exception',
        tag: 'ClockApi',
        error: e,
        stackTrace: stackTrace,
      );
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
