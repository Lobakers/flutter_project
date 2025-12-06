import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
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
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        final response = await ApiService.get(context, Api.attendance_profile);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Cache the data for offline use
          await OfflineDatabase.saveAttendanceProfile(data);

          debugPrint('✅ Fetched attendance profile from API and cached');
          return {"success": true, "data": data};
        } else {
          return {
            "success": false,
            "message": "Failed to load attendance profile",
          };
        }
      } else {
        // OFFLINE: Return cached data
        final cachedProfile = await OfflineDatabase.getAttendanceProfile();
        if (cachedProfile != null) {
          debugPrint('📱 Loaded attendance profile from offline cache');
          return {"success": true, "data": cachedProfile};
        } else {
          return {
            "success": false,
            "message": "No cached attendance profile available",
          };
        }
      }
    } catch (e) {
      debugPrint('❌ AttendanceProfileApi error: $e');

      // On error, try to return cached data as fallback
      try {
        final cachedProfile = await OfflineDatabase.getAttendanceProfile();
        if (cachedProfile != null) {
          debugPrint('⚠️ Using cached attendance profile due to error');
          return {"success": true, "data": cachedProfile};
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached attendance profile: $cacheError');
      }

      return {"success": false, "message": "Network error: $e"};
    }
  }
}
