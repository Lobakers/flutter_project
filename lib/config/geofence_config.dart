/// Centralized configuration for all geofence-related distance values
///
/// This class contains all distance constants used throughout the application.
/// By centralizing these values, you can change one constant and it will
/// automatically update all related functionality and user-facing messages.
class GeofenceConfig {
  // ==================== DISTANCE CONSTANTS ====================

  /// Auto Clock-Out Radius (foreground & background monitoring)
  /// This is the distance threshold for automatic clock-out when user moves away
  static const double autoClockOutRadius = 250.0;

  /// Client Filtering Radius (for nearby clients dropdown)
  /// This determines which clients appear in the dropdown based on proximity
  static const double clientFilterRadius = 1000.0;

  /// Map Display Radius (visual circle on map)
  /// This is the radius of the circle shown on the map when geofence is active
  static const double mapDisplayRadius = 1000.0;

  // ==================== HELPER METHODS ====================

  /// Get auto clock-out radius as formatted text (e.g., "250m")
  static String get autoClockOutRadiusText =>
      '${autoClockOutRadius.toStringAsFixed(0)}m';

  /// Get client filter radius as formatted text (e.g., "1000m")
  static String get clientFilterRadiusText =>
      '${clientFilterRadius.toStringAsFixed(0)}m';

  /// Get map display radius as formatted text (e.g., "1000m")
  static String get mapDisplayRadiusText =>
      '${mapDisplayRadius.toStringAsFixed(0)}m';

  // ==================== USER-FACING MESSAGES ====================

  /// Message shown when no clients are found within the filter radius
  static String getNoClientsFoundMessage(double radius) =>
      'No clients found within ${radius.toStringAsFixed(0)}m of your location. '
      'Try refreshing your location or move closer to a client site.';

  /// Get a formatted message for distance from target location
  /// Used in debug logs and user notifications
  static String getDistanceMessage(double distance) =>
      '${distance.toStringAsFixed(0)}m';
}
