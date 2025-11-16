import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _userInfo;

  // GETTERS
  String? get token => _token;
  Map<String, dynamic>? get userInfo => _userInfo;

  bool get isLoggedIn => _token != null;

  // SET TOKEN
  void setToken(String token) {
    _token = token;
    notifyListeners();
  }

  // SET USER INFO
  void setUserInfo(Map<String, dynamic> info) {
    _userInfo = info;
    notifyListeners();
  }

  // LOGOUT
  void logout() {
    _token = null;
    _userInfo = null;
    notifyListeners();
  }
}
