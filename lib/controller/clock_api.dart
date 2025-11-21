import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
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
        "projectId": projectId ?? "",
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
      };

      final response = await ApiService.post(context, Api.clock, body);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          "success": true,
          "clockLogGuid": data[0]['CLOCK_LOG_GUID'],
          "clockTime": data[0]['CLOCK_TIME'],
        };
      } else {
        return {"success": false, "message": "Clock in failed"};
      }
    } catch (e) {
      debugPrint('ClockIn error: $e');
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
    required String clockRefGuid, // Links to the clock in record
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
        "projectId": projectId ?? "",
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
        "clockRefGuid": clockRefGuid, // Required for clock out!
      };

      final response = await ApiService.post(context, Api.clock, body);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {"success": true, "clockTime": data[0]['CLOCK_TIME']};
      } else {
        return {"success": false, "message": "Clock out failed"};
      }
    } catch (e) {
      debugPrint('ClockOut error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }

  /// Get latest clock status
  static Future<Map<String, dynamic>> getLatestClock(
    BuildContext context,
  ) async {
    try {
      final response = await ApiService.get(context, Api.clock_beewhere);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.isEmpty) {
          return {"success": true, "isClockedIn": false};
        }

        final latest = data[0];
        final clockType = latest['CLOCK_TYPE'];

        return {
          "success": true,
          "isClockedIn": clockType == 0, // 0 = clocked in, 1 = clocked out
          "clockLogGuid": latest['CLOCK_LOG_GUID'],
          "clockTime": latest['CLOCK_TIME'],
          "jobType": latest['JOB_TYPE'],
          "address": latest['ADDRESS'],
          "clientId": latest['CLIENT_ID'],
          "projectId": latest['PROJECT_GUID'],
          "contractId": latest['CONTRACT_GUID'],
          "activityName": latest['ACTIVITY']?['NAME'],
        };
      } else {
        return {"success": false, "message": "Failed to get clock status"};
      }
    } catch (e) {
      debugPrint('GetLatestClock error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
