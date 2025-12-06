import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Service to manage offline actions queue
/// Handles write operations performed while offline
class PendingSyncService {
  static Database? _database;
  static bool _isInitialized = false;

  /// Initialize the pending sync database
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dbPath = join(appDocDir.path, 'beewhere_pending_sync.db');

      _database = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE pending_sync (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              action_type TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL,
              retry_count INTEGER DEFAULT 0,
              last_error TEXT
            )
          ''');

          // Create index for faster queries
          await db.execute(
            'CREATE INDEX idx_created_at ON pending_sync(created_at ASC)',
          );
        },
      );

      _isInitialized = true;
      debugPrint('✅ PendingSyncService initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize pending sync database: $e');
    }
  }

  /// Add a pending action to the queue
  static Future<void> addPendingAction({
    required String actionType,
    required Map<String, dynamic> payload,
  }) async {
    if (_database == null) return;

    try {
      await _database!.insert('pending_sync', {
        'action_type': actionType,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
      });

      debugPrint('✅ Added pending action: $actionType');
    } catch (e) {
      debugPrint('❌ Failed to add pending action: $e');
    }
  }

  /// Get all pending actions
  static Future<List<Map<String, dynamic>>> getPendingActions() async {
    if (_database == null) return [];

    try {
      final results = await _database!.query(
        'pending_sync',
        orderBy: 'created_at ASC',
      );

      return results.map((row) {
        return {
          'id': row['id'],
          'action_type': row['action_type'],
          'payload': jsonDecode(row['payload'] as String),
          'created_at': row['created_at'],
          'retry_count': row['retry_count'],
          'last_error': row['last_error'],
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Failed to get pending actions: $e');
      return [];
    }
  }

  /// Get count of pending actions
  static Future<int> getPendingCount() async {
    if (_database == null) return 0;

    try {
      final result = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM pending_sync',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('❌ Failed to get pending count: $e');
      return 0;
    }
  }

  /// Remove a pending action after successful sync
  static Future<void> removePendingAction(int id) async {
    if (_database == null) return;

    try {
      await _database!.delete('pending_sync', where: 'id = ?', whereArgs: [id]);

      debugPrint('✅ Removed pending action: $id');
    } catch (e) {
      debugPrint('❌ Failed to remove pending action: $e');
    }
  }

  /// Increment retry count for a failed sync
  static Future<void> incrementRetry(int id, String error) async {
    if (_database == null) return;

    try {
      await _database!.rawUpdate(
        'UPDATE pending_sync SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
        [error, id],
      );

      debugPrint('⚠️ Incremented retry count for action: $id');
    } catch (e) {
      debugPrint('❌ Failed to increment retry: $e');
    }
  }

  /// Clear all pending actions (use with caution)
  static Future<void> clearAll() async {
    if (_database == null) return;

    try {
      await _database!.delete('pending_sync');
      debugPrint('✅ Cleared all pending actions');
    } catch (e) {
      debugPrint('❌ Failed to clear pending actions: $e');
    }
  }

  /// Close database connection
  static Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}
