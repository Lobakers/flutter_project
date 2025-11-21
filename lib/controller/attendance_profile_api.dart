import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class AttendanceProfileApi {
  /// Fetches attendance profile configuration
  /// Returns which buttons (Office/Site/Home/Others) to show
  /// And which fields (client/project/contract/activity) to show for each
  static Future<Map<String, dynamic>> getAttendanceProfile(
    BuildContext context,
  ) async {
    try {
      final response = await ApiService.get(context, Api.attendance_profile);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {"success": true, "data": data};
      } else {
        return {
          "success": false,
          "message": "Failed to load attendance profile",
        };
      }
    } catch (e) {
      debugPrint('AttendanceProfileApi error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
