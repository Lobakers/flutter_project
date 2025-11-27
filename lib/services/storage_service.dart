import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for securely storing sensitive data like tokens and user info
/// Uses flutter_secure_storage for encrypted storage on device
class StorageService {
  static const _storage = FlutterSecureStorage();

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyUserInfo = 'user_info';
  static const String _keyClockInState = 'clock_in_state';

  /// Save JWT token securely
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// Retrieve stored JWT token
  static Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  /// Delete stored token
  static Future<void> deleteToken() async {
    await _storage.delete(key: _keyToken);
  }

  /// Save user info as JSON
  static Future<void> saveUserInfo(Map<String, dynamic> userInfo) async {
    final jsonString = jsonEncode(userInfo);
    await _storage.write(key: _keyUserInfo, value: jsonString);
  }

  /// Retrieve stored user info
  static Future<Map<String, dynamic>?> getUserInfo() async {
    final jsonString = await _storage.read(key: _keyUserInfo);
    if (jsonString == null) return null;

    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      // If JSON parsing fails, return null
      return null;
    }
  }

  /// Delete stored user info
  static Future<void> deleteUserInfo() async {
    await _storage.delete(key: _keyUserInfo);
  }

  /// Save clock-in state for background tracking
  static Future<void> saveClockInState({
    required bool isClockedIn,
    required String? clockRefGuid,
    required double? targetLat,
    required double? targetLng,
    required String? targetAddress,
    required double? radiusInMeters,
    String? jobType,
    String? clientId,
    String? projectId,
    String? contractId,
  }) async {
    final state = {
      'isClockedIn': isClockedIn,
      'clockRefGuid': clockRefGuid,
      'targetLat': targetLat,
      'targetLng': targetLng,
      'targetAddress': targetAddress,
      'radiusInMeters': radiusInMeters,
      'jobType': jobType,
      'clientId': clientId,
      'projectId': projectId,
      'contractId': contractId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    final jsonString = jsonEncode(state);
    await _storage.write(key: _keyClockInState, value: jsonString);
  }

  /// Get clock-in state
  static Future<Map<String, dynamic>?> getClockInState() async {
    final jsonString = await _storage.read(key: _keyClockInState);
    if (jsonString == null) return null;

    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Clear clock-in state
  static Future<void> clearClockInState() async {
    await _storage.delete(key: _keyClockInState);
  }

  /// Clear all stored data (use on logout)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Check if user has stored credentials
  static Future<bool> hasStoredCredentials() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
