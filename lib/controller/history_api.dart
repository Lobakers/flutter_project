import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/routes/api.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/pending_sync_service.dart';
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
    int offset = 0,
  }) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        String url = '${Api.report}/$limit/$offset/all';
        debugPrint('📋 GetAttendanceHistory Request: $url');

        final response = await ApiService.get(context, url);
        debugPrint('📋 GetAttendanceHistory Response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Handle both array and object responses
          List<dynamic> records = [];
          if (data is List) {
            records = data;
          } else if (data is Map && data.containsKey('data')) {
            records = data['data'] as List<dynamic>;
          }

          // Cache the data for offline use
          await OfflineDatabase.saveAttendanceHistory(records);

          debugPrint(
            '✅ GetAttendanceHistory Success: ${records.length} records cached',
          );
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
      } else {
        // OFFLINE: Return cached data
        final cachedRecords = await OfflineDatabase.getAttendanceHistory(
          limit: limit,
        );
        debugPrint(
          '📱 Loaded ${cachedRecords.length} records from offline cache',
        );
        return {
          'success': true,
          'data': cachedRecords,
          'count': cachedRecords.length,
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ GetAttendanceHistory Exception: $e');
      debugPrint('Stack trace: $stackTrace');

      // On error, try to return cached data as fallback
      try {
        final cachedRecords = await OfflineDatabase.getAttendanceHistory(
          limit: limit,
        );
        if (cachedRecords.isNotEmpty) {
          debugPrint('⚠️ Using cached history due to error');
          return {
            'success': true,
            'data': cachedRecords,
            'count': cachedRecords.length,
          };
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached history: $cacheError');
      }

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

  // ... (Keep getClockDetail, updateActivity, submitTimeRequest as they were) ...
  // I've omitted them here for brevity since they don't need changes.

  /// Get clock detail by GUID
  static Future<Map<String, dynamic>> getClockDetail(
    BuildContext context,
    String clockGuid,
  ) async {
    try {
      final url = '${Api.clock_detail}/$clockGuid';
      debugPrint('📋 GetClockDetail Request: $url');

      final response = await ApiService.get(context, url);

      debugPrint('📋 GetClockDetail Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ GetClockDetail Success');
        return {'success': true, 'data': data};
      } else {
        debugPrint('❌ GetClockDetail Failed: ${response.statusCode}');
        return {'success': false, 'message': 'Failed to fetch clock details'};
      }
    } catch (e) {
      debugPrint('❌ GetClockDetail Exception: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Update activity for a clock record
  static Future<Map<String, dynamic>> updateActivity(
    BuildContext context,
    String clockLogGuid,
    List<Map<String, dynamic>> activities,
  ) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Send to API
        final url = Api.clock_activity;
        final payload = {'clockLogGuid': clockLogGuid, 'activity': activities};

        debugPrint('📋 UpdateActivity Request: $url');
        debugPrint('   Payload: ${jsonEncode(payload)}');

        final response = await ApiService.patch(context, url, payload);

        debugPrint('📋 UpdateActivity Response: ${response.statusCode}');

        if (response.statusCode == 200) {
          debugPrint('✅ UpdateActivity Success');
          return {'success': true, 'message': 'Activity updated successfully'};
        } else {
          debugPrint('❌ UpdateActivity Failed: ${response.statusCode}');
          return {'success': false, 'message': 'Failed to update activity'};
        }
      } else {
        // OFFLINE: Queue for later sync
        await PendingSyncService.addPendingAction(
          actionType: 'update_activity',
          payload: {'clockLogGuid': clockLogGuid, 'activity': activities},
        );
        debugPrint('📱 UpdateActivity queued for offline sync');
        return {
          'success': true,
          'message': 'Saved offline. Will sync when online.',
        };
      }
    } catch (e) {
      debugPrint('❌ UpdateActivity Exception: $e');

      // On error, queue for offline sync
      try {
        await PendingSyncService.addPendingAction(
          actionType: 'update_activity',
          payload: {'clockLogGuid': clockLogGuid, 'activity': activities},
        );
        return {
          'success': true,
          'message': 'Saved offline due to error. Will sync when online.',
        };
      } catch (queueError) {
        debugPrint('❌ Failed to queue activity update: $queueError');
      }

      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Submit time change request
  static Future<Map<String, dynamic>> submitTimeRequest(
    BuildContext context, {
    required String userGuid,
    required String userEmail,
    required int startTime,
    required int endTime,
    required String description,
    String? supportingDoc,
  }) async {
    final payload = {
      'requestType': 'clocks',
      'subject': 'Wrong clock out time',
      'starttime': startTime,
      'endtime': endTime,
      'supportingDoc': supportingDoc ?? '',
      'description': description,
      'userGuid': userGuid,
      'userEmail': userEmail,
    };

    try {
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        final url = Api.support;
        debugPrint('📋 SubmitTimeRequest Request: $url');
        debugPrint('   Payload: ${jsonEncode(payload)}');

        final response = await ApiService.post(context, url, payload);

        debugPrint('📋 SubmitTimeRequest Response: ${response.statusCode}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✅ SubmitTimeRequest Success');
          return {'success': true, 'message': 'Request submitted successfully'};
        } else {
          debugPrint('❌ SubmitTimeRequest Failed: ${response.statusCode}');
          return {'success': false, 'message': 'Failed to submit request'};
        }
      } else {
        // OFFLINE: Queue for later sync
        await PendingSyncService.addPendingAction(
          actionType: 'submit_time_request',
          payload: payload,
        );
        debugPrint('📱 SubmitTimeRequest queued for offline sync');
        return {
          'success': true,
          'message': 'Saved offline. Will sync when online.',
        };
      }
    } catch (e) {
      debugPrint('❌ SubmitTimeRequest Exception: $e');

      // On error, queue for offline sync
      try {
        await PendingSyncService.addPendingAction(
          actionType: 'submit_time_request',
          payload: payload,
        );
        return {
          'success': true,
          'message': 'Saved offline due to error. Will sync when online.',
        };
      } catch (queueError) {
        debugPrint('❌ Failed to queue time request: $queueError');
      }

      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
