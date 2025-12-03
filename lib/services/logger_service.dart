import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Centralized logging service with SQLite storage
/// Replaces all debugPrint calls with structured logging
class LoggerService {
  static Database? _database;
  static Logger? _logger;
  static bool _isInitialized = false;

  // Log levels
  static const String levelDebug = 'DEBUG';
  static const String levelInfo = 'INFO';
  static const String levelWarning = 'WARNING';
  static const String levelError = 'ERROR';

  /// Initialize the logger service
  static Future<void> init() async {
    if (_isInitialized) return;

    // Initialize logger with custom configuration
    _logger = Logger(
      filter: ProductionFilter(), // Only log in debug mode by default
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      output: _LogOutput(),
    );

    // Initialize database for log storage
    await _initDatabase();

    _isInitialized = true;
    info('LoggerService initialized');
  }

  /// Initialize SQLite database for log storage
  static Future<void> _initDatabase() async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dbPath = join(appDocDir.path, 'beewhere_logs.db');

      _database = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              level TEXT NOT NULL,
              tag TEXT,
              message TEXT NOT NULL,
              stackTrace TEXT
            )
          ''');

          // Create index for faster queries
          await db.execute(
            'CREATE INDEX idx_timestamp ON logs(timestamp DESC)',
          );
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize log database: $e');
    }
  }

  /// Save log to database
  static Future<void> _saveToDatabase({
    required String level,
    required String message,
    String? tag,
    String? stackTrace,
  }) async {
    if (_database == null) return;

    try {
      await _database!.insert('logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'level': level,
        'tag': tag,
        'message': message,
        'stackTrace': stackTrace,
      });

      // Keep only last 1000 logs to prevent database bloat
      await _cleanOldLogs();
    } catch (e) {
      debugPrint('Failed to save log to database: $e');
    }
  }

  /// Clean old logs (keep only last 1000)
  static Future<void> _cleanOldLogs() async {
    if (_database == null) return;

    try {
      final count = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT COUNT(*) FROM logs'),
      );

      if (count != null && count > 1000) {
        await _database!.rawDelete(
          'DELETE FROM logs WHERE id NOT IN (SELECT id FROM logs ORDER BY timestamp DESC LIMIT 1000)',
        );
      }
    } catch (e) {
      debugPrint('Failed to clean old logs: $e');
    }
  }

  /// Get logs from database
  static Future<List<Map<String, dynamic>>> getLogs({
    String? level,
    int limit = 100,
  }) async {
    if (_database == null) return [];

    try {
      String query = 'SELECT * FROM logs';
      List<dynamic> args = [];

      if (level != null) {
        query += ' WHERE level = ?';
        args.add(level);
      }

      query += ' ORDER BY timestamp DESC LIMIT ?';
      args.add(limit);

      return await _database!.rawQuery(query, args);
    } catch (e) {
      debugPrint('Failed to get logs: $e');
      return [];
    }
  }

  /// Clear all logs from database
  static Future<void> clearLogs() async {
    if (_database == null) return;

    try {
      await _database!.delete('logs');
      info('All logs cleared');
    } catch (e) {
      debugPrint('Failed to clear logs: $e');
    }
  }

  /// Debug level log
  static void debug(String message, {String? tag}) {
    if (!_isInitialized) {
      debugPrint('[DEBUG] $message');
      return;
    }

    _logger?.d(tag != null ? '[$tag] $message' : message);
    _saveToDatabase(level: levelDebug, message: message, tag: tag);
  }

  /// Info level log
  static void info(String message, {String? tag}) {
    if (!_isInitialized) {
      debugPrint('[INFO] $message');
      return;
    }

    _logger?.i(tag != null ? '[$tag] $message' : message);
    _saveToDatabase(level: levelInfo, message: message, tag: tag);
  }

  /// Warning level log
  static void warning(String message, {String? tag}) {
    if (!_isInitialized) {
      debugPrint('[WARNING] $message');
      return;
    }

    _logger?.w(tag != null ? '[$tag] $message' : message);
    _saveToDatabase(level: levelWarning, message: message, tag: tag);
  }

  /// Error level log
  static void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (!_isInitialized) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('Error: $error');
      if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
      return;
    }

    _logger?.e(
      tag != null ? '[$tag] $message' : message,
      error: error,
      stackTrace: stackTrace,
    );

    _saveToDatabase(
      level: levelError,
      message: message,
      tag: tag,
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Close database connection
  static Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}

/// Custom log output that only logs in debug mode
class _LogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    // Only output logs in debug mode
    if (kDebugMode) {
      for (var line in event.lines) {
        debugPrint(line);
      }
    }
  }
}

/// Production filter - only log warnings and errors in production
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) {
      return true; // Log everything in debug mode
    } else {
      // In production, only log warnings and errors
      return event.level.index >= Level.warning.index;
    }
  }
}
