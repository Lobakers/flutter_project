import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/routes/api.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:flutter/material.dart';

/// API service for fetching report data
class ReportApi {
  /// Get report data by type and date range
  /// type: 'attendance' or 'activity'
  /// startTimestamp: Unix timestamp in seconds
  /// endTimestamp: Unix timestamp in seconds
  static Future<Map<String, dynamic>> getReport(
    BuildContext context,
    String type,
    int startTimestamp,
    int endTimestamp,
  ) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        final url = '${Api.report_history}/$type/$startTimestamp/$endTimestamp';

        debugPrint('📋 GetReport Request: $url');

        final response = await ApiService.get(context, url);
        debugPrint('📋 GetReport Response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Cache the data for offline use
          await OfflineDatabase.saveReportData(
            reportType: type,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            data: data,
          );

          debugPrint('✅ GetReport Success and cached');
          return {'success': true, 'data': data};
        } else {
          debugPrint('❌ GetReport Failed: ${response.statusCode}');
          return {'success': false, 'message': 'Failed to fetch report data'};
        }
      } else {
        // OFFLINE: Return cached data
        final cachedData = await OfflineDatabase.getReportData(
          reportType: type,
          startTimestamp: startTimestamp,
          endTimestamp: endTimestamp,
        );

        if (cachedData != null) {
          debugPrint('📱 Loaded report from offline cache');
          return {'success': true, 'data': cachedData};
        } else {
          return {
            'success': false,
            'message': 'No cached report data available',
          };
        }
      }
    } catch (e) {
      debugPrint('❌ GetReport Exception: $e');

      // On error, try to return cached data as fallback
      try {
        final cachedData = await OfflineDatabase.getReportData(
          reportType: type,
          startTimestamp: startTimestamp,
          endTimestamp: endTimestamp,
        );

        if (cachedData != null) {
          debugPrint('⚠️ Using cached report due to error');
          return {'success': true, 'data': cachedData};
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached report: $cacheError');
      }

      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
