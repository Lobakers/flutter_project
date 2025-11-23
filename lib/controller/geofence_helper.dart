import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeofenceHelper {
  /// Default radius in meters
  static const double defaultRadius = 500.0;

  /// Calculate distance between two points using Haversine formula
  /// Returns distance in meters
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // You can also use Geolocator's built-in method:
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Check if user is outside the geofence radius
  /// Returns true if user is MORE than [radius] meters away from target
  static bool isOutsideRadius({
    required double userLat,
    required double userLng,
    required double targetLat,
    required double targetLng,
    double radius = defaultRadius,
  }) {
    final distance = calculateDistance(userLat, userLng, targetLat, targetLng);
    debugPrint(
      '📍 Distance from site: ${distance.toStringAsFixed(2)}m (radius: ${radius}m)',
    );
    return distance > radius;
  }

  /// Manual Haversine calculation (alternative if Geolocator not available)
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // Earth's radius in meters

    // Convert to radians
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    // Haversine formula
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Distance in meters
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
