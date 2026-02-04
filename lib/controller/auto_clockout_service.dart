import 'dart:async';
import 'package:beewhere/controller/geofence_helper.dart';
import 'package:beewhere/config/geofence_config.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Callback when user leaves the geofence area
typedef OnLeaveGeofence = Future<void> Function(double distance);

class AutoClockOutService {
  Timer? _checkTimer; // ✨ Changed from position stream to timer
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isMonitoring = false;

  // Target location (client/site location)
  double? _targetLat;
  double? _targetLng;
  String? _targetAddress;

  // Settings
  final Duration checkInterval;
  double radiusInMeters; // ✨ Made non-final to allow dynamic updates

  // Callback when user exits geofence
  OnLeaveGeofence? onLeaveGeofence;

  // Stream for UI updates
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  // ✨ GPS drift protection
  int _violationCount = 0;
  int _requiredViolations = GeofenceConfig.requiredViolations;
  
  // ✨ Minimum time before auto clock-out can trigger (prevents immediate trigger)
  DateTime? _monitoringStartTime;
  static const Duration _minimumClockInDuration = Duration(seconds: 30);

  AutoClockOutService({
    this.checkInterval = GeofenceConfig.autoClockOutCheckInterval,
    this.radiusInMeters = GeofenceConfig.autoClockOutRadius,
    this.onLeaveGeofence,
  });

  bool get isMonitoring => _isMonitoring;
  double? get targetLat => _targetLat;
  double? get targetLng => _targetLng;
  String? get targetAddress => _targetAddress;

  /// Start monitoring user location
  Future<void> startMonitoring({
    required double targetLat,
    required double targetLng,
    String? targetAddress,
    double? radiusInMeters, // ✨ Optional override
  }) async {
    if (_isMonitoring) {
      debugPrint('⚠️ Already monitoring, stopping previous session');
      stopMonitoring();
    }

    _targetLat = targetLat;
    _targetLng = targetLng;
    _targetAddress = targetAddress;
    // ✨ Use override if provided, otherwise fallback to default
    if (radiusInMeters != null) {
      this.radiusInMeters = radiusInMeters;
    }
    _isMonitoring = true;
    _violationCount = 0; // Reset violation counter
    _monitoringStartTime = DateTime.now(); // ✨ Track when monitoring started

    debugPrint('🎯 Started geofence monitoring');
    debugPrint('   Target: $_targetLat, $_targetLng');
    debugPrint('   Radius: ${this.radiusInMeters}m');
    debugPrint('   Check interval: ${checkInterval.inSeconds}s');
    debugPrint('   Required violations: $_requiredViolations');
    debugPrint('   Minimum duration: ${_minimumClockInDuration.inSeconds}s');

    // Start location service monitoring
    _startLocationServiceMonitoring();

    // ✨ NEW: Use Timer.periodic instead of position stream
    // This respects the configured checkInterval (e.g., 3 minutes)
    _checkTimer = Timer.periodic(checkInterval, (timer) async {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }
      
      try {
        // Get current position
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        
        await _checkLocation(position);
      } catch (e) {
        debugPrint('❌ Error getting position: $e');
        
        // Check if error is due to location service being disabled
        final isEnabled = await _checkLocationServiceStatus();
        if (!isEnabled) {
          debugPrint('🚨 Location service disabled (detected via error)');
          
          // Trigger callback
          if (onLeaveGeofence != null) {
            await onLeaveGeofence!(-1.0);
          }
          
          stopMonitoring();
        }
      }
    });
    
    // ✨ Do an immediate first check (don't wait for first interval)
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _checkLocation(position);
    } catch (e) {
      debugPrint('❌ Error on initial position check: $e');
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _locationServiceCheckTimer?.cancel();
    _locationServiceCheckTimer = null;
    _isMonitoring = false;
    _targetLat = null;
    _targetLng = null;
    _targetAddress = null;
    _violationCount = 0; // Reset counter
    _monitoringStartTime = null; // ✨ Reset monitoring start time
    debugPrint('🛑 Stopped geofence monitoring');
  }

  /// Check current location against target
  Future<void> _checkLocation(Position position) async {
    if (!_isMonitoring || _targetLat == null || _targetLng == null) {
      return;
    }

    try {
      debugPrint(
        '📍 Current location: ${position.latitude}, ${position.longitude}',
      );

      // Calculate distance
      final distance = GeofenceHelper.calculateDistance(
        position.latitude,
        position.longitude,
        _targetLat!,
        _targetLng!,
      );

      debugPrint('📏 Distance from target: ${distance.toStringAsFixed(2)}m');

      // ✨ NEW: Check if outside radius (with violation counter)
      if (distance > radiusInMeters) {
        // ✨ Check if minimum time has elapsed since monitoring started
        if (_monitoringStartTime != null) {
          final elapsed = DateTime.now().difference(_monitoringStartTime!);
          if (elapsed < _minimumClockInDuration) {
            debugPrint(
              '⏰ Too soon for auto clock-out (${elapsed.inSeconds}s / ${_minimumClockInDuration.inSeconds}s). Ignoring violation.',
            );
            return; // Don't count violations yet
          }
        }

        _violationCount++;
        debugPrint(
          '⚠️ Violation $_violationCount/$_requiredViolations: ${distance.toStringAsFixed(2)}m > ${radiusInMeters}m',
        );

        // Only trigger if consecutive violations exceed threshold
        if (_violationCount >= _requiredViolations) {
          debugPrint(
            '🚨 User CONFIRMED OUTSIDE geofence! Distance: ${distance.toStringAsFixed(2)}m',
          );

          // Trigger callback
          if (onLeaveGeofence != null) {
            await onLeaveGeofence!(distance);
          }

          // Stop monitoring after triggering
          stopMonitoring();
        } else {
          debugPrint(
            '⏳ Waiting for confirmation... ($_violationCount/$_requiredViolations)',
          );
        }
      } else {
        // Back inside - reset counter
        if (_violationCount > 0) {
          debugPrint(
            '🔄 Back inside geofence! Resetting violation count (was $_violationCount)',
          );
        }
        _violationCount = 0;
        debugPrint(
          '✅ User is inside geofence (${distance.toStringAsFixed(2)}m < ${radiusInMeters}m)',
        );
      }

      // Emit status update to UI
      _statusController.add({
        'userLat': position.latitude,
        'userLng': position.longitude,
        'targetLat': _targetLat,
        'targetLng': _targetLng,
        'distance': distance,
        'isInside': distance <= radiusInMeters,
        'radius': radiusInMeters,
        'violationCount': _violationCount,
      });
    } catch (e) {
      debugPrint('❌ Error checking location: $e');
    }
  }

  /// Check if location services are enabled
  /// Returns true if enabled, false if disabled
  Future<bool> _checkLocationServiceStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      return serviceEnabled;
    } catch (e) {
      debugPrint('❌ Error checking location service status: $e');
      return false;
    }
  }

  /// Start periodic check for location service status
  Timer? _locationServiceCheckTimer;

  void _startLocationServiceMonitoring() {
    // Check every 5 seconds if location service is still enabled
    _locationServiceCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) async {
        if (!_isMonitoring) {
          timer.cancel();
          return;
        }

        final isEnabled = await _checkLocationServiceStatus();
        if (!isEnabled) {
          debugPrint('🚨 Location service DISABLED! Triggering auto clock-out');
          
          // Trigger callback with a special distance value (-1) to indicate location disabled
          if (onLeaveGeofence != null) {
            await onLeaveGeofence!(-1.0);
          }

          // Stop monitoring
          stopMonitoring();
        }
      },
    );
  }

  /// Manually check location (for testing or refresh button)
  Future<Map<String, dynamic>> checkNow() async {
    if (_targetLat == null || _targetLng == null) {
      return {'error': 'No target location set'};
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final distance = GeofenceHelper.calculateDistance(
        position.latitude,
        position.longitude,
        _targetLat!,
        _targetLng!,
      );

      return {
        'userLat': position.latitude,
        'userLng': position.longitude,
        'targetLat': _targetLat,
        'targetLng': _targetLng,
        'distance': distance,
        'isInside': distance <= radiusInMeters,
        'radius': radiusInMeters,
        'violationCount': _violationCount,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}
