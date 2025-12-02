import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:beewhere/services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _userInfo;
  bool _isLoading = false;

  // GETTERS
  String? get token => _token;
  Map<String, dynamic>? get userInfo => _userInfo;
  bool get isLoggedIn => _token != null;
  bool get isLoading => _isLoading;

  // SET TOKEN (with persistent storage)
  Future<void> setToken(String token) async {
    _token = token;
    await StorageService.saveToken(token);
    notifyListeners();
  }

  // SET USER INFO (with persistent storage)
  Future<void> setUserInfo(Map<String, dynamic> info) async {
    _userInfo = info;
    await StorageService.saveUserInfo(info);
    notifyListeners();
  }

  // CHECK IF TOKEN IS EXPIRED
  bool _isTokenExpired(String token) {
    try {
      // JWT tokens have 3 parts separated by dots: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) {
        debugPrint('Invalid token format');
        return true;
      }

      // Decode the payload (second part)
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );

      // Get expiration timestamp (exp is in seconds since epoch)
      final exp = payload['exp'];
      if (exp == null) {
        debugPrint('Token has no expiration field');
        return true;
      }

      // Convert to DateTime and compare with current time
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      final isExpired = DateTime.now().isAfter(expiryDate);

      if (isExpired) {
        debugPrint('Token expired at: $expiryDate');
      } else {
        final remaining = expiryDate.difference(DateTime.now());
        debugPrint(
          'Token valid for: ${remaining.inHours}h ${remaining.inMinutes % 60}m',
        );
      }

      return isExpired;
    } catch (e) {
      debugPrint('Error checking token expiration: $e');
      return true; // If we can't decode, consider it expired
    }
  }

  // LOAD STORED AUTHENTICATION (for auto-login)
  Future<bool> loadStoredAuth() async {
    _isLoading = true;
    // notifyListeners(); // Removed to prevent setState during build error in SplashScreen

    try {
      final storedToken = await StorageService.getToken();
      final storedUserInfo = await StorageService.getUserInfo();

      if (storedToken != null && storedUserInfo != null) {
        // ✅ Check if token is expired before auto-login
        if (_isTokenExpired(storedToken)) {
          debugPrint('Stored token is expired. Clearing credentials.');
          await StorageService.clearAll();
          _isLoading = false;
          notifyListeners();
          return false; // Token expired, require fresh login
        }

        // Token is valid, restore session
        _token = storedToken;
        _userInfo = storedUserInfo;
        _isLoading = false;
        notifyListeners();
        debugPrint('Auto-login successful with valid token');
        return true; // Successfully restored session
      }
    } catch (e) {
      debugPrint('Error loading stored auth: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false; // No stored session
  }

  // LOGOUT (clear storage)
  Future<void> logout() async {
    _token = null;
    _userInfo = null;
    await StorageService.clearAll();
    notifyListeners();
  }
}
