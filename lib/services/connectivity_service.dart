import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service to monitor internet connectivity and trigger sync
class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<ConnectivityResult>? _subscription;
  static bool _isOnline = true;
  static final List<Function()> _syncCallbacks = [];

  /// Initialize connectivity monitoring
  static void init() {
    // Check initial connectivity
    checkConnectivity();

    // Listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      _handleConnectivityChange(result);
    });

    debugPrint('✅ ConnectivityService initialized');
  }

  /// Handle connectivity changes
  static void _handleConnectivityChange(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    debugPrint('📡 Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');

    // If we just came online, trigger sync
    if (!wasOnline && _isOnline) {
      debugPrint('🔄 Connection restored, triggering sync...');
      _triggerSync();
    }
  }

  /// Check current connectivity status
  static Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = result != ConnectivityResult.none;
      return _isOnline;
    } catch (e) {
      debugPrint('❌ Error checking connectivity: $e');
      return false;
    }
  }

  /// Check if currently online
  static bool get isOnline => _isOnline;

  /// Register a callback to be called when connection is restored
  static void registerSyncCallback(Function() callback) {
    _syncCallbacks.add(callback);
  }

  /// Unregister a sync callback
  static void unregisterSyncCallback(Function() callback) {
    _syncCallbacks.remove(callback);
  }

  /// Trigger all registered sync callbacks
  static void _triggerSync() {
    for (var callback in _syncCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('❌ Error in sync callback: $e');
      }
    }
  }

  /// Manually trigger sync (for testing or manual refresh)
  static void triggerManualSync() {
    if (_isOnline) {
      debugPrint('🔄 Manual sync triggered');
      _triggerSync();
    } else {
      debugPrint('⚠️ Cannot sync: offline');
    }
  }

  /// Dispose connectivity service
  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _syncCallbacks.clear();
  }
}
