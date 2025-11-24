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
        "projectGuid": projectId ?? "", // 👈 FIXED: was "projectId"
        "contractId": contractId ?? "",
        "userAgent": {
          "description": deviceDescription,
          "publicIP": deviceIp,
          "deviceID": deviceId,
        },
        "activity": {"name": activityName ?? "", "statusFlag": "true"},
      };

      debugPrint('🔵 ClockIn Request:');
      debugPrint('   URL: ${Api.clock}');
      debugPrint('   Body: ${jsonEncode(body)}');

      final response = await ApiService.post(context, Api.clock, body);

      debugPrint('🔵 ClockIn Response:');
      debugPrint('   Status: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ ClockIn Success: $data');

        return {
          "success": true,
          "clockLogGuid": data[0]['CLOCK_LOG_GUID'],
          "clockTime": data[0]['CLOCK_TIME'],
        };
      } else {
        debugPrint('❌ ClockIn Failed: Status ${response.statusCode}');
        return {
          "success": false,
          "message": "Clock in failed: ${response.body}",
        };
      }
    } catch (e) {
      debugPrint('❌ ClockIn Exception: $e');
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

      debugPrint('🔴 ClockOut Request:');
      debugPrint('   URL: ${Api.clock}');
      debugPrint('   Body: ${jsonEncode(body)}');

      final response = await ApiService.post(context, Api.clock, body);

      debugPrint('🔴 ClockOut Response:');
      debugPrint('   Status: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ ClockOut Success: $data');

        return {"success": true, "clockTime": data[0]['CLOCK_TIME']};
      } else {
        debugPrint('❌ ClockOut Failed: Status ${response.statusCode}');
        return {
          "success": false,
          "message": "Clock out failed: ${response.body}",
        };
      }
    } catch (e) {
      debugPrint('❌ ClockOut Exception: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }

  /// Get latest clock status
  static Future<Map<String, dynamic>> getLatestClock(
    BuildContext context,
  ) async {
    try {
      debugPrint('📋 GetLatestClock Request: ${Api.clock_beewhere}');

      final response = await ApiService.get(context, Api.clock_beewhere);

      debugPrint('📋 GetLatestClock Response:');
      debugPrint('   Status: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('📋 Parsed data type: ${data.runtimeType}');
        debugPrint('📋 Parsed data: $data');

        if (data.isEmpty) {
          debugPrint('ℹ️ No clock records found');
          return {"success": true, "isClockedIn": false};
        }

        debugPrint('📋 Data is list: ${data is List}');
        debugPrint('📋 Data length: ${data is List ? data.length : 'N/A'}');

        final latest = data[0];
        debugPrint('📋 Latest record: $latest');

        final clockType = latest['CLOCK_TYPE'];
        debugPrint('📋 Clock type: $clockType');

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
        debugPrint('❌ GetLatestClock Failed: Status ${response.statusCode}');
        return {"success": false, "message": "Failed to get clock status"};
      }
    } catch (e, stackTrace) {
      debugPrint('❌ GetLatestClock Exception: $e');
      debugPrint('Stack trace: $stackTrace');
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
