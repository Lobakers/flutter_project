import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:beewhere/controller/geofence_helper.dart';

/// Callback when user leaves the geofence area
typedef OnLeaveGeofence = Future<void> Function(double distance);

class AutoClockOutService {
  Timer? _timer;
  bool _isMonitoring = false;

  // Target location (client/site location)
  double? _targetLat;
  double? _targetLng;
  String? _targetAddress;

  // Settings
  final Duration checkInterval;
  final double radiusInMeters;

  // Callback when user exits geofence
  OnLeaveGeofence? onLeaveGeofence;

  // ✨ NEW: GPS drift protection
  int _violationCount = 0;
  final int _requiredViolations = 2; // Must be outside 3 times in a row

  AutoClockOutService({
    this.checkInterval = const Duration(minutes: 1),
    this.radiusInMeters = 500.0,
    this.onLeaveGeofence,
  });

  bool get isMonitoring => _isMonitoring;
  double? get targetLat => _targetLat;
  double? get targetLng => _targetLng;
  String? get targetAddress => _targetAddress;

  /// Start monitoring user location
  void startMonitoring({
    required double targetLat,
    required double targetLng,
    String? targetAddress,
  }) {
    if (_isMonitoring) {
      debugPrint('⚠️ Already monitoring, stopping previous session');
      stopMonitoring();
    }

    _targetLat = targetLat;
    _targetLng = targetLng;
    _targetAddress = targetAddress;
    _isMonitoring = true;
    _violationCount = 0; // Reset violation counter

    debugPrint('🎯 Started geofence monitoring');
    debugPrint('   Target: $_targetLat, $_targetLng');
    debugPrint('   Radius: ${radiusInMeters}m');
    debugPrint('   Check interval: ${checkInterval.inSeconds}s');
    debugPrint('   Required violations: $_requiredViolations');

    // Start periodic check
    _timer = Timer.periodic(checkInterval, (_) => _checkLocation());

    // Also check immediately
    _checkLocation();
  }

  /// Stop monitoring
  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _isMonitoring = false;
    _targetLat = null;
    _targetLng = null;
    _targetAddress = null;
    _violationCount = 0; // Reset counter
    debugPrint('🛑 Stopped geofence monitoring');
  }

  /// Check current location against target
  Future<void> _checkLocation() async {
    if (!_isMonitoring || _targetLat == null || _targetLng == null) {
      return;
    }

    try {
      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

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
    } catch (e) {
      debugPrint('❌ Error checking location: $e');
    }
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
  }
}
