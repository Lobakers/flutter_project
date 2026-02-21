import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      debugPrint('📡 Connectivity status: ${isOnline ? 'ONLINE' : 'OFFLINE'}');

      if (isOnline) {
        // ONLINE: Fetch from API
        debugPrint('🔄 Fetching attendance profile from API...');

        // Check auth token first
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final token = authProvider.token;
        debugPrint(
          '🔐 Auth token present: ${token != null ? 'YES (${token.length} chars)' : 'NO'}',
        );
        if (token == null) {
          debugPrint(
            '⚠️ WARNING: No auth token found! User may not be logged in.',
          );
        }

        final response = await ApiService.get(context, Api.attendance_profile);

        debugPrint('📊 API Response Status: ${response.statusCode}');
        debugPrint('📊 API URL: ${Api.attendance_profile}');
        debugPrint('📊 API Response Body: ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Cache the data for offline use
          await OfflineDatabase.saveAttendanceProfile(data);

          debugPrint('✅ Fetched attendance profile from API and cached');
          return {"success": true, "data": data};
        } else {
          final errorMsg =
              'API returned status ${response.statusCode}: ${response.body}';
          debugPrint('❌ $errorMsg');
          return {"success": false, "message": errorMsg};
        }
      } else {
        // OFFLINE: Return cached data
        debugPrint('📱 Attempting to load from offline cache...');
        final cachedProfile = await OfflineDatabase.getAttendanceProfile();
        if (cachedProfile != null) {
          debugPrint('📱 ✅ Loaded attendance profile from offline cache');
          return {"success": true, "data": cachedProfile};
        } else {
          debugPrint('📱 ❌ No cached attendance profile available');
          return {
            "success": false,
            "message": "No cached attendance profile available",
          };
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ AttendanceProfileApi error: $e');
      debugPrint('Stack trace: $stackTrace');

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
