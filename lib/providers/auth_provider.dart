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

  // LOAD STORED AUTHENTICATION (for auto-login)
  Future<bool> loadStoredAuth() async {
    _isLoading = true;
    // notifyListeners(); // Removed to prevent setState during build error in SplashScreen

    try {
      final storedToken = await StorageService.getToken();
      final storedUserInfo = await StorageService.getUserInfo();

      if (storedToken != null && storedUserInfo != null) {
        _token = storedToken;
        _userInfo = storedUserInfo;
        _isLoading = false;
        notifyListeners();
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
