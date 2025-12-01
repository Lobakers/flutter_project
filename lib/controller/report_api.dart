import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/routes/api.dart';
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
      final url = '${Api.report_history}/$type/$startTimestamp/$endTimestamp';

      debugPrint('📋 GetReport Request: $url');
      debugPrint('   Type: $type');
      debugPrint('   Start: $startTimestamp');
      debugPrint('   End: $endTimestamp');

      final response = await ApiService.get(context, url);

      debugPrint('📋 GetReport Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint('✅ GetReport Success');

        return {'success': true, 'data': data};
      } else {
        debugPrint('❌ GetReport Failed: ${response.statusCode}');
        return {'success': false, 'message': 'Failed to fetch report data'};
      }
    } catch (e) {
      debugPrint('❌ GetReport Exception: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
