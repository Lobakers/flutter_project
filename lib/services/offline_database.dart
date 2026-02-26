import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Unified offline database service for caching all API data
/// Provides local storage for offline mode functionality
class OfflineDatabase {
  static Database? _database;
  static bool _isInitialized = false;

  /// Initialize the offline database
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dbPath = join(appDocDir.path, 'beewhere_offline.db');

      _database = await openDatabase(
        dbPath,
        version: 1,
        singleInstance: false, // ✨ Prevent cross-isolate closure
        onCreate: (Database db, int version) async {
          // Attendance History Table
          await db.execute('''
            CREATE TABLE attendance_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              clock_log_guid TEXT UNIQUE NOT NULL,
              clock_in_time TEXT,
              clock_out_time TEXT,
              job_type TEXT,
              client_name TEXT,
              address_in TEXT,
              address_out TEXT,
              activities TEXT,
              synced INTEGER DEFAULT 1,
              created_at TEXT,
              updated_at TEXT
            )
          ''');

          // Clock Status Table (single row)
          await db.execute('''
            CREATE TABLE clock_status (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              is_clocked_in INTEGER DEFAULT 0,
              clock_log_guid TEXT,
              clock_time TEXT,
              job_type TEXT,
              address TEXT,
              client_id TEXT,
              project_id TEXT,
              contract_id TEXT,
              activity_name TEXT,
              updated_at TEXT
            )
          ''');

          // Clients Table
          await db.execute('''
            CREATE TABLE clients (
              client_guid TEXT PRIMARY KEY,
              name TEXT,
              abbr TEXT,
              location_data TEXT,
              updated_at TEXT
            )
          ''');

          // Projects Table
          await db.execute('''
            CREATE TABLE projects (
              project_guid TEXT PRIMARY KEY,
              name TEXT,
              data TEXT,
              updated_at TEXT
            )
          ''');

          // Contracts Table
          await db.execute('''
            CREATE TABLE contracts (
              contract_id TEXT PRIMARY KEY,
              name TEXT,
              data TEXT,
              updated_at TEXT
            )
          ''');

          // Attendance Profile Table
          await db.execute('''
            CREATE TABLE attendance_profile (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              profile_data TEXT,
              updated_at TEXT
            )
          ''');

          // Report Data Table
          await db.execute('''
            CREATE TABLE report_data (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              report_type TEXT,
              start_timestamp INTEGER,
              end_timestamp INTEGER,
              data TEXT,
              created_at TEXT
            )
          ''');

          // User Profile Table
          await db.execute('''
            CREATE TABLE user_profile (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              user_data TEXT,
              updated_at TEXT
            )
          ''');

          // Create indexes for faster queries
          await db.execute(
            'CREATE INDEX idx_attendance_created ON attendance_history(created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX idx_report_type ON report_data(report_type, start_timestamp, end_timestamp)',
          );
        },
      );

      // ✨ Integrity Check after initialization
      try {
        final List<Map<String, dynamic>> integrity = await _database!.rawQuery(
          'PRAGMA integrity_check',
        );
        if (integrity.isNotEmpty &&
            integrity.first['integrity_check'] != 'ok') {
          debugPrint('❌ Database integrity check FAILED: $integrity');
          debugPrint('🧹 Attempting safe recovery by deleting corrupted DB');

          await _database!.close();
          await deleteDatabase(dbPath);

          // Re-initialize after deletion
          _isInitialized = false;
          await init();
          return;
        } else {
          debugPrint('✅ Database integrity check passed');
        }
      } catch (checkError) {
        debugPrint('⚠️ DB Integrity check skipped (Error: $checkError)');
      }

      _isInitialized = true;
      debugPrint('✅ OfflineDatabase initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize offline database: $e');
    }
  }

  /// ✨ Auto-healing database getter
  /// Re-initializes if database is null or closed
  /// Throws a StateError if the DB cannot be opened after retry.
  static Future<Database> _getDb() async {
    if (_database == null || !_database!.isOpen) {
      _isInitialized = false;
      await init();

      // If still not open after init, retry once after brief delay
      if (_database == null || !_database!.isOpen) {
        await Future.delayed(const Duration(milliseconds: 200));
        _isInitialized = false;
        await init();
      }

      if (_database == null || !_database!.isOpen) {
        throw StateError(
          'OfflineDatabase: failed to open database after retry',
        );
      }
    }
    return _database!;
  }

  // ==================== ATTENDANCE HISTORY ====================

  /// Save attendance history records from API
  static Future<void> saveAttendanceHistory(List<dynamic> records) async {
    final db = await _getDb();

    try {
      final now = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        for (var record in records) {
          final activities = record['ACTIVITY'] != null
              ? jsonEncode(record['ACTIVITY'])
              : null;

          await txn.insert('attendance_history', {
            'clock_log_guid': record['CLOCK_LOG_GUID'],
            'clock_in_time': record['CLOCK_IN_TIME'],
            'clock_out_time': record['CLOCK_OUT_TIME'],
            'job_type': record['JOB_TYPE'],
            'client_name': record['CLIENT_NAME'],
            'address_in': record['ADDRESS_IN'],
            'address_out': record['ADDRESS_OUT'],
            'activities': activities,
            'synced': 1,
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      debugPrint('✅ Saved ${records.length} attendance records to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save attendance history: $e');
    }
  }

  /// Get cached attendance history
  static Future<List<Map<String, dynamic>>> getAttendanceHistory({
    int limit = 100,
  }) async {
    final db = await _getDb();

    try {
      final results = await db.query(
        'attendance_history',
        orderBy: 'created_at DESC',
        limit: limit,
      );

      // Convert back to API format
      return results.map((row) {
        Map<String, dynamic> record = {
          'CLOCK_LOG_GUID': row['clock_log_guid'],
          'CLOCK_IN_TIME': row['clock_in_time'],
          'CLOCK_OUT_TIME': row['clock_out_time'],
          'JOB_TYPE': row['job_type'],
          'CLIENT_NAME': row['client_name'],
          'ADDRESS_IN': row['address_in'],
          'ADDRESS_OUT': row['address_out'],
        };

        // Parse activities JSON
        if (row['activities'] != null) {
          record['ACTIVITY'] = jsonDecode(row['activities'] as String);
        }

        return record;
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get attendance history: $e');
      return [];
    }
  }

  // ==================== CLOCK STATUS ====================

  /// Save latest clock status
  static Future<void> saveClockStatus(Map<String, dynamic> status) async {
    try {
      final db = await _getDb();

      final isClockedIn = status['isClockedIn'] == true ? 1 : 0;

      debugPrint(
        '💾 Saving clock status to offline DB: isClockedIn=$isClockedIn, clockLogGuid=${status['clockLogGuid']}',
      );

      await db.insert('clock_status', {
        'id': 1,
        'is_clocked_in': isClockedIn,
        'clock_log_guid': status['clockLogGuid'],
        'clock_time': status['clockTime'],
        'job_type': status['jobType'],
        'address': status['address'],
        'client_id': status['clientId'],
        'project_id': status['projectId'],
        'contract_id': status['contractId'],
        'activity_name': status['activityName'],
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint('✅ Clock status saved successfully to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save clock status: $e');
    }
  }

  /// Get cached clock status
  static Future<Map<String, dynamic>?> getClockStatus() async {
    try {
      final db = await _getDb();

      final results = await db.query(
        'clock_status',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (results.isEmpty) {
        debugPrint('⚠️ No clock status found in cache');
        return null;
      }

      final row = results.first;
      final isClockedIn = row['is_clocked_in'] == 1;

      debugPrint(
        '📱 Reading clock status from cache: isClockedIn=$isClockedIn, clockLogGuid=${row['clock_log_guid']}',
      );

      return {
        'success': true,
        'isClockedIn': isClockedIn,
        'clockLogGuid': row['clock_log_guid'],
        'clockTime': row['clock_time'],
        'jobType': row['job_type'],
        'address': row['address'],
        'clientId': row['client_id'],
        'projectId': row['project_id'],
        'contractId': row['contract_id'],
        'activityName': row['activity_name'],
      };
    } catch (e) {
      debugPrint('❌ Failed to get clock status: $e');
      return null;
    }
  }

  // ==================== CLIENTS ====================

  /// Save clients list
  static Future<void> saveClients(List<dynamic> clients) async {
    final db = await _getDb();

    try {
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();

      for (var client in clients) {
        batch.insert('clients', {
          'client_guid': client['CLIENT_GUID'],
          'name': client['NAME'],
          'abbr': client['ABBR'],
          'location_data': jsonEncode(client['LOCATION_DATA']),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Saved ${clients.length} clients to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save clients: $e');
    }
  }

  /// Get cached clients
  static Future<List<dynamic>> getClients() async {
    final db = await _getDb();

    try {
      final results = await db.query('clients');

      return results.map((row) {
        return {
          'CLIENT_GUID': row['client_guid'],
          'NAME': row['name'],
          'ABBR': row['abbr'],
          'LOCATION_DATA': jsonDecode(row['location_data'] as String),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get clients: $e');
      return [];
    }
  }

  // ==================== PROJECTS ====================

  /// Save projects list
  static Future<void> saveProjects(List<dynamic> projects) async {
    final db = await _getDb();

    try {
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();

      for (var project in projects) {
        batch.insert('projects', {
          'project_guid': project['PROJECT_GUID'] ?? project['GUID'],
          'name': project['NAME'] ?? project['PROJECT_NAME'],
          'data': jsonEncode(project),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Saved ${projects.length} projects to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save projects: $e');
    }
  }

  /// Get cached projects
  static Future<List<dynamic>> getProjects() async {
    final db = await _getDb();

    try {
      final results = await db.query('projects');
      return results.map((row) => jsonDecode(row['data'] as String)).toList();
    } catch (e) {
      debugPrint('❌ Failed to get projects: $e');
      return [];
    }
  }

  // ==================== CONTRACTS ====================

  /// Save contracts list
  static Future<void> saveContracts(List<dynamic> contracts) async {
    final db = await _getDb();

    try {
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();

      for (var contract in contracts) {
        batch.insert('contracts', {
          'contract_id': contract['CONTRACT_ID'] ?? contract['ID'],
          'name': contract['NAME'] ?? contract['CONTRACT_NAME'],
          'data': jsonEncode(contract),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Saved ${contracts.length} contracts to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save contracts: $e');
    }
  }

  /// Get cached contracts
  static Future<List<dynamic>> getContracts() async {
    final db = await _getDb();

    try {
      final results = await db.query('contracts');
      return results.map((row) => jsonDecode(row['data'] as String)).toList();
    } catch (e) {
      debugPrint('❌ Failed to get contracts: $e');
      return [];
    }
  }

  // ==================== ATTENDANCE PROFILE ====================

  /// Save attendance profile configuration
  static Future<void> saveAttendanceProfile(
    Map<String, dynamic> profile,
  ) async {
    final db = await _getDb();

    try {
      await db.insert('attendance_profile', {
        'id': 1,
        'profile_data': jsonEncode(profile),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      debugPrint('✅ Saved attendance profile to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save attendance profile: $e');
    }
  }

  /// Get cached attendance profile
  static Future<Map<String, dynamic>?> getAttendanceProfile() async {
    final db = await _getDb();

    try {
      final results = await db.query(
        'attendance_profile',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (results.isEmpty) return null;

      return jsonDecode(results.first['profile_data'] as String);
    } catch (e) {
      debugPrint('❌ Failed to get attendance profile: $e');
      return null;
    }
  }

  // ==================== REPORT DATA ====================

  /// Save report data
  static Future<void> saveReportData({
    required String reportType,
    required int startTimestamp,
    required int endTimestamp,
    required dynamic data,
  }) async {
    final db = await _getDb();

    try {
      await db.insert('report_data', {
        'report_type': reportType,
        'start_timestamp': startTimestamp,
        'end_timestamp': endTimestamp,
        'data': jsonEncode(data),
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      debugPrint('✅ Saved report data to offline DB');
    } catch (e) {
      debugPrint('❌ Failed to save report data: $e');
    }
  }

  /// Get cached report data
  static Future<dynamic> getReportData({
    required String reportType,
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final db = await _getDb();

    try {
      final results = await db.query(
        'report_data',
        where: 'report_type = ? AND start_timestamp = ? AND end_timestamp = ?',
        whereArgs: [reportType, startTimestamp, endTimestamp],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (results.isEmpty) return null;

      return jsonDecode(results.first['data'] as String);
    } catch (e) {
      debugPrint('❌ Failed to get report data: $e');
      return null;
    }
  }

  // ==================== CLEANUP ====================

  /// Clear old data (keep last 30 days)
  static Future<void> clearOldData() async {
    final db = await _getDb();

    try {
      final cutoffDate = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String();

      // Clear old attendance history
      await db.delete(
        'attendance_history',
        where: 'created_at < ?',
        whereArgs: [cutoffDate],
      );

      // Clear old report data
      await db.delete(
        'report_data',
        where: 'created_at < ?',
        whereArgs: [cutoffDate],
      );

      debugPrint('✅ Cleared old offline data');
    } catch (e) {
      debugPrint('❌ Failed to clear old data: $e');
    }
  }

  /// Close database connection
  static Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}
