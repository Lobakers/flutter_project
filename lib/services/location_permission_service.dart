import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../widgets/prominent_disclosure_dialog.dart';

/// Service to handle location permissions with Google Play compliant disclosure
class LocationPermissionService {
  /// Check if all required location permissions are granted
  static Future<bool> hasAllPermissions() async {
    final foreground = await Geolocator.checkPermission();
    final background = await ph.Permission.locationAlways.status;

    return (foreground == LocationPermission.always ||
            foreground == LocationPermission.whileInUse) &&
        background.isGranted;
  }

  /// Check if background location permission is granted
  static Future<bool> hasBackgroundPermission() async {
    final status = await ph.Permission.locationAlways.status;
    return status.isGranted;
  }

  /// Request location permissions with prominent disclosure
  /// Returns true if all permissions are granted, false otherwise
  static Future<bool> requestLocationPermissions(BuildContext context) async {
    try {
      // Step 1: Check if permissions are already granted
      if (await hasAllPermissions()) {
        debugPrint('✅ All location permissions already granted');
        return true;
      }

      // Step 2: Show prominent disclosure BEFORE requesting any permissions
      final userAcceptedDisclosure = await _showProminentDisclosure(context);
      if (!userAcceptedDisclosure) {
        debugPrint('❌ User declined disclosure');
        return false;
      }

      // Step 3: Request foreground location
      final foregroundGranted = await _requestForegroundLocation(context);
      if (!foregroundGranted) {
        debugPrint('❌ Foreground location permission denied');
        return false;
      }

      // Step 4: Check if background location is already granted
      if (await hasBackgroundPermission()) {
        debugPrint('✅ Background location already granted');
        return true;
      }

      // Step 5: Request background location permission
      // Note: This opens Android settings and the app goes to background
      // Add a small delay after returning to ensure app state is stable
      final backgroundGranted = await _requestBackgroundLocation();

      // Wait a bit for app to stabilize after returning from settings
      await Future.delayed(const Duration(milliseconds: 500));

      if (!backgroundGranted) {
        debugPrint('❌ Background location permission denied');
        return false;
      }

      debugPrint('✅ All location permissions granted');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ CRASH PREVENTED: Error during permission request: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Request foreground location permission
  static Future<bool> _requestForegroundLocation(BuildContext context) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      debugPrint('🔵 Foreground permission status: ${permission.toString()}');

      if (permission == LocationPermission.denied) {
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e, stackTrace) {
      debugPrint('❌ CRASH PREVENTED: Error requesting foreground location: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Show prominent disclosure dialog
  /// Returns true if user accepts, false if user declines
  static Future<bool> _showProminentDisclosure(BuildContext context) async {
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ProminentDisclosureDialog(
        onAccept: () => Navigator.of(dialogContext).pop(true),
        onDecline: () => Navigator.of(dialogContext).pop(false),
      ),
    );

    return result ?? false;
  }

  /// Request background location permission
  static Future<bool> _requestBackgroundLocation() async {
    try {
      final status = await ph.Permission.locationAlways.request();
      // debugPrint('🔵 Background permission status: ${status.toString()}');
      return status.isGranted;
    } catch (e) {
      // debugPrint('❌ CRASH PREVENTED: Error requesting background location: $e');
      return false;
    }
  }

  /// Check if location services are enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Open app settings for manual permission grant
  static Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  /// Get current permission status for debugging
  static Future<Map<String, dynamic>> getPermissionStatus() async {
    final foreground = await Geolocator.checkPermission();
    final background = await ph.Permission.locationAlways.status;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    return {
      'foreground': foreground.toString(),
      'background': background.toString(),
      'serviceEnabled': serviceEnabled,
    };
  }
}
