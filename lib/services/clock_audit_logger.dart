import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Persistent audit logger for CRITICAL clock operations
/// Helps debug production issues like "I clocked out but app still says clocked in"
///
/// This logger stores critical state changes permanently to help troubleshoot:
/// - Clock in/out transactions
/// - Storage layer updates (Memory, SQLite, Secure Storage)
/// - Background service lifecycle
/// - Auto clock-out triggers
/// - Permission changes
/// - Service watchdog restarts
class ClockAuditLogger {
  static Database? _database;
  static bool _isInitialized = false;

  // Real-time stream for live updates
  static final StreamController<Map<String, dynamic>> _logStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get logStream =>
      _logStreamController.stream;

  // Event types for categorization
  static const String eventClockIn = 'CLOCK_IN';
  static const String eventClockOut = 'CLOCK_OUT';
  static const String eventStorageUpdate = 'STORAGE_UPDATE';
  static const String eventServiceStart = 'SERVICE_START';
  static const String eventServiceStop = 'SERVICE_STOP';
  static const String eventServiceRestart = 'SERVICE_RESTART';
  static const String eventAutoClockOut = 'AUTO_CLOCK_OUT';
  static const String eventPermissionChange = 'PERMISSION_CHANGE';
  static const String eventStateMismatch = 'STATE_MISMATCH';
  static const String eventSyncComplete = 'SYNC_COMPLETE';
  static const String eventSyncAttempt = 'SYNC_ATTEMPT'; // ✨ NEW
  static const String eventSyncBlocked = 'SYNC_BLOCKED'; // ✨ NEW
  static const String eventSyncStart = 'SYNC_START'; // ✨ NEW
  static const String eventActionSynced = 'ACTION_SYNCED'; // ✨ NEW
  static const String eventActionSyncFailed = 'ACTION_SYNC_FAILED'; // ✨ NEW
  static const String eventConnectivityChange = 'CONNECTIVITY_CHANGE'; // ✨ NEW
  static const String eventError = 'ERROR';

  /// Initialize the audit logger
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dbPath = join(appDocDir.path, 'beewhere_clock_audit.db');

      _database = await openDatabase(
        dbPath,
        version: 1,
        singleInstance: false,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE clock_audit (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              event_type TEXT NOT NULL,
              description TEXT NOT NULL,
              clock_ref_guid TEXT,
              user_id TEXT,
              storage_layer TEXT,
              metadata TEXT,
              is_online INTEGER DEFAULT 1
            )
          ''');

          // Create indices for faster queries
          await db.execute(
            'CREATE INDEX idx_timestamp ON clock_audit(timestamp DESC)',
          );
          await db.execute(
            'CREATE INDEX idx_event_type ON clock_audit(event_type)',
          );
          await db.execute(
            'CREATE INDEX idx_clock_ref ON clock_audit(clock_ref_guid)',
          );
        },
      );

      _isInitialized = true;
      await _log(
        eventType: eventServiceStart,
        description: 'ClockAuditLogger initialized',
        metadata: 'App startup',
      );
    } catch (e) {
      debugPrint('❌ Failed to initialize ClockAuditLogger: $e');
    }
  }

  /// Internal logging method
  static Future<void> _log({
    required String eventType,
    required String description,
    String? clockRefGuid,
    String? userId,
    String? storageLayer,
    String? metadata,
    bool isOnline = true,
  }) async {
    if (_database == null) {
      debugPrint('⚠️ ClockAuditLogger not initialized, skipping log');
      return;
    }

    try {
      final timestamp = DateTime.now().toIso8601String();
      final logEntry = {
        'timestamp': timestamp,
        'event_type': eventType,
        'description': description,
        'clock_ref_guid': clockRefGuid,
        'user_id': userId,
        'storage_layer': storageLayer,
        'metadata': metadata,
        'is_online': isOnline ? 1 : 0,
      };

      await _database!.insert('clock_audit', logEntry);

      // Broadcast to real-time listeners
      _logStreamController.add(logEntry);

      // Also print to console for immediate visibility
      debugPrint(
        '🔍 AUDIT [$eventType] $description ${metadata != null ? "($metadata)" : ""}',
      );

      // Keep only last 2000 entries to prevent database bloat
      await _cleanOldEntries();
    } catch (e) {
      debugPrint('❌ Failed to write audit log: $e');
    }
  }

  /// Clean old entries (keep only last 2000)
  static Future<void> _cleanOldEntries() async {
    if (_database == null) return;

    try {
      final count = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT COUNT(*) FROM clock_audit'),
      );

      if (count != null && count > 2000) {
        await _database!.rawDelete(
          'DELETE FROM clock_audit WHERE id NOT IN (SELECT id FROM clock_audit ORDER BY timestamp DESC LIMIT 2000)',
        );
      }
    } catch (e) {
      debugPrint('Failed to clean old audit logs: $e');
    }
  }

  /// Public logging method (wrapper for _log)
  static Future<void> log({
    required String eventType,
    required String description,
    String? clockRefGuid,
    String? userId,
    String? storageLayer,
    String? metadata,
    bool isOnline = true,
  }) async {
    await _log(
      eventType: eventType,
      description: description,
      clockRefGuid: clockRefGuid,
      userId: userId,
      storageLayer: storageLayer,
      metadata: metadata,
      isOnline: isOnline,
    );
  }

  // ==================== PUBLIC LOGGING METHODS ====================

  /// Log clock-in start
  static Future<void> logClockIn({
    required String clockRefGuid,
    required String userId,
    required bool isOnline,
    String? metadata,
  }) async {
    await _log(
      eventType: eventClockIn,
      description: 'Clock-in initiated',
      clockRefGuid: clockRefGuid,
      userId: userId,
      metadata: metadata,
      isOnline: isOnline,
    );
  }

  /// Log clock-out start
  static Future<void> logClockOut({
    required String clockRefGuid,
    required String userId,
    required bool isOnline,
    bool isAutomatic = false,
    String? reason,
  }) async {
    await _log(
      eventType: eventClockOut,
      description: isAutomatic ? 'Automatic clock-out' : 'Manual clock-out',
      clockRefGuid: clockRefGuid,
      userId: userId,
      metadata: reason,
      isOnline: isOnline,
    );
  }

  /// Log storage layer update (Memory, SQLite, Secure Storage)
  static Future<void> logStorageUpdate({
    required String layer,
    required String operation,
    String? clockRefGuid,
    String? details,
  }) async {
    await _log(
      eventType: eventStorageUpdate,
      description: '$operation in $layer',
      clockRefGuid: clockRefGuid,
      storageLayer: layer,
      metadata: details,
    );
  }

  /// Log background service start
  static Future<void> logServiceStart({
    required String serviceType,
    String? clockRefGuid,
    String? targetLocation,
  }) async {
    await _log(
      eventType: eventServiceStart,
      description: '$serviceType service started',
      clockRefGuid: clockRefGuid,
      metadata: targetLocation,
    );
  }

  /// Log background service stop
  static Future<void> logServiceStop({
    required String serviceType,
    String? reason,
  }) async {
    await _log(
      eventType: eventServiceStop,
      description: '$serviceType service stopped',
      metadata: reason,
    );
  }

  /// Log service watchdog restart
  static Future<void> logServiceRestart({
    required String serviceType,
    String? clockRefGuid,
    required String reason,
  }) async {
    await _log(
      eventType: eventServiceRestart,
      description: 'Watchdog restarted $serviceType',
      clockRefGuid: clockRefGuid,
      metadata: reason,
    );
  }

  /// Log auto clock-out trigger
  static Future<void> logAutoClockOut({
    required String clockRefGuid,
    required String userId,
    required String trigger,
    required double distance,
    required bool isOnline,
  }) async {
    await _log(
      eventType: eventAutoClockOut,
      description: 'Auto clock-out triggered by $trigger',
      clockRefGuid: clockRefGuid,
      userId: userId,
      metadata: 'Distance: ${distance.toStringAsFixed(2)}m',
      isOnline: isOnline,
    );
  }

  /// Log permission change
  static Future<void> logPermissionChange({
    required String permissionType,
    required String status,
  }) async {
    await _log(
      eventType: eventPermissionChange,
      description: '$permissionType permission: $status',
      metadata: 'User action required',
    );
  }

  /// Log state mismatch between local and server
  static Future<void> logStateMismatch({
    required String localState,
    required String serverState,
    String? clockRefGuid,
  }) async {
    await _log(
      eventType: eventStateMismatch,
      description: 'State mismatch detected',
      clockRefGuid: clockRefGuid,
      metadata: 'Local: $localState, Server: $serverState',
    );
  }

  /// Log offline sync completion
  static Future<void> logSyncComplete({
    required int syncedCount,
    required int failedCount,
    String? clockRefGuid,
  }) async {
    await _log(
      eventType: eventSyncComplete,
      description: 'Offline sync completed',
      clockRefGuid: clockRefGuid,
      metadata: 'Synced: $syncedCount, Failed: $failedCount',
    );
  }

  /// Log errors
  static Future<void> logError({
    required String operation,
    required String error,
    String? clockRefGuid,
    String? userId,
  }) async {
    await _log(
      eventType: eventError,
      description: 'Error during $operation',
      clockRefGuid: clockRefGuid,
      userId: userId,
      metadata: error,
    );
  }

  // ==================== QUERY METHODS ====================

  /// Get recent audit logs
  static Future<List<Map<String, dynamic>>> getRecentLogs({
    int limit = 100,
  }) async {
    if (_database == null) return [];

    try {
      return await _database!.query(
        'clock_audit',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('Failed to get audit logs: $e');
      return [];
    }
  }

  /// Get logs for specific clock reference
  static Future<List<Map<String, dynamic>>> getLogsForClock({
    required String clockRefGuid,
  }) async {
    if (_database == null) return [];

    try {
      return await _database!.query(
        'clock_audit',
        where: 'clock_ref_guid = ?',
        whereArgs: [clockRefGuid],
        orderBy: 'timestamp DESC',
      );
    } catch (e) {
      debugPrint('Failed to get logs for clock: $e');
      return [];
    }
  }

  /// Get logs by event type
  static Future<List<Map<String, dynamic>>> getLogsByType({
    required String eventType,
    int limit = 50,
  }) async {
    if (_database == null) return [];

    try {
      return await _database!.query(
        'clock_audit',
        where: 'event_type = ?',
        whereArgs: [eventType],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('Failed to get logs by type: $e');
      return [];
    }
  }

  /// Clear all audit logs
  static Future<void> clearLogs() async {
    if (_database == null) return;

    try {
      await _database!.delete('clock_audit');
      await _log(
        eventType: eventServiceStart,
        description: 'Audit logs cleared',
        metadata: 'User action',
      );
    } catch (e) {
      debugPrint('Failed to clear audit logs: $e');
    }
  }

  /// Export logs as text (for user support tickets)
  static Future<String> exportLogsAsText({int limit = 500}) async {
    final logs = await getRecentLogs(limit: limit);
    final buffer = StringBuffer();

    buffer.writeln('BeeWhere Clock Audit Log Export');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Entries: ${logs.length}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (var log in logs) {
      buffer.writeln('[${log['timestamp']}] ${log['event_type']}');
      buffer.writeln('  ${log['description']}');
      if (log['clock_ref_guid'] != null) {
        buffer.writeln('  GUID: ${log['clock_ref_guid']}');
      }
      if (log['metadata'] != null) {
        buffer.writeln('  Details: ${log['metadata']}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// ✨ Log sync attempt (when sync is triggered)
  static Future<void> logSyncAttempt({
    required String trigger,
    required int pendingCount,
  }) async {
    await _log(
      eventType: eventSyncAttempt,
      description: 'Sync triggered by: $trigger',
      metadata: 'Pending actions: $pendingCount',
    );
  }

  /// ✨ Log sync blocked (when sync cannot proceed)
  static Future<void> logSyncBlocked({
    required String reason,
    required String details,
  }) async {
    await _log(
      eventType: eventSyncBlocked,
      description: 'Sync blocked: $reason',
      metadata: details,
    );
  }

  /// ✨ Log sync start (when sync begins processing)
  static Future<void> logSyncStart({
    required int pendingCount,
    required String details,
  }) async {
    await _log(
      eventType: eventSyncStart,
      description: 'Sync started - $pendingCount actions to process',
      metadata: details,
    );
  }

  /// ✨ Log action synced successfully
  static Future<void> logActionSynced({
    required String actionType,
    required int actionId,
    required int retryCount,
  }) async {
    await _log(
      eventType: eventActionSynced,
      description: 'Action $actionType synced successfully (ID: $actionId)',
      metadata: 'Retry count: $retryCount',
    );
  }

  /// ✨ Log action sync failed
  static Future<void> logActionSyncFailed({
    required String actionType,
    required int actionId,
    required int retryCount,
    required String reason,
  }) async {
    await _log(
      eventType: eventActionSyncFailed,
      description: 'Action $actionType sync failed (ID: $actionId)',
      metadata: 'Retry count: $retryCount, Reason: $reason',
    );
  }

  /// ✨ Log connectivity change
  static Future<void> logConnectivityChange({
    required bool isOnline,
    required bool previousState,
    required String connectionType,
  }) async {
    final change = isOnline ? 'OFFLINE → ONLINE' : 'ONLINE → OFFLINE';
    await _log(
      eventType: eventConnectivityChange,
      description: 'Connectivity changed: $change',
      metadata: 'Connection type: $connectionType',
    );
  }

  /// Close database connection
  static Future<void> dispose() async {
    await _logStreamController.close();
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}
