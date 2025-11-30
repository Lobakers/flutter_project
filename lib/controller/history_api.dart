import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/routes/api.dart';
import 'package:flutter/material.dart';

/// API service for fetching attendance history
class HistoryApi {
  /// Get attendance history for a date range
  /// Returns list of clock in/out records
  static Future<Map<String, dynamic>> getAttendanceHistory(
    BuildContext context, {
    String? startDate,
    String? endDate,
    int limit = 5,
    int page = 1,
  }) async {
    try {
      // Build query parameters
      // API: /clock/history-list/{limit}/{page}/{type}
      String url = '${Api.report}/$limit/$page/all';

      debugPrint('📋 GetAttendanceHistory Request: $url');

      final response = await ApiService.get(context, url);

      debugPrint('📋 GetAttendanceHistory Response:');
      debugPrint('   Status: ${response.statusCode}');
      debugPrint('   Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Handle both array and object responses
        List<dynamic> records = [];
        if (data is List) {
          records = data;
        } else if (data is Map && data.containsKey('data')) {
          records = data['data'] as List<dynamic>;
        }

        debugPrint('✅ GetAttendanceHistory Success: ${records.length} records');

        return {'success': true, 'data': records, 'count': records.length};
      } else {
        debugPrint(
          '❌ GetAttendanceHistory Failed: Status ${response.statusCode}',
        );
        return {
          'success': false,
          'message': 'Failed to fetch attendance history',
          'data': [],
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ GetAttendanceHistory Exception: $e');
      debugPrint('Stack trace: $stackTrace');
      return {'success': false, 'message': 'Network error: $e', 'data': []};
    }
  }

  /// Calculate total hours worked from records
  static double calculateTotalHours(List<dynamic> records) {
    double totalHours = 0.0;

    for (var record in records) {
      if (record['CLOCK_IN_TIME'] != null && record['CLOCK_OUT_TIME'] != null) {
        try {
          final clockIn = DateTime.parse(record['CLOCK_IN_TIME']);
          final clockOut = DateTime.parse(record['CLOCK_OUT_TIME']);
          final duration = clockOut.difference(clockIn);
          totalHours += duration.inMinutes / 60.0;
        } catch (e) {
          debugPrint('Error parsing time for record: $e');
        }
      }
    }

    return totalHours;
  }
}
