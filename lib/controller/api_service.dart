import 'dart:convert';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

class ApiService {
  /// Check if response is 401 (Unauthorized) and handle auto-logout
  static Future<void> _handle401(
    BuildContext context,
    http.Response response,
  ) async {
    if (response.statusCode == 401) {
      debugPrint('🔴 401 Unauthorized - Token expired, logging out...');

      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.logout();

      // Navigate to login page and clear all routes
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);

        // Show snackbar to inform user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            backgroundColor: Color(0xFFD32F2F),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  static Future<http.Response> get(BuildContext context, String url) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'JWT $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    // Check for token expiration
    await _handle401(context, response);

    return response;
  }

  static Future<http.Response> post(
    BuildContext context,
    String url,
    Map<String, dynamic> body, {
    Duration? timeout, // Allow custom timeout for specific calls
  }) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'JWT $token',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout ?? const Duration(seconds: 20));

    // Check for token expiration
    await _handle401(context, response);

    return response;
  }

  static Future<http.Response> patch(
    BuildContext context,
    String url,
    Map<String, dynamic> body,
  ) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    final response = await http
        .patch(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'JWT $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    // Check for token expiration
    await _handle401(context, response);

    return response;
  }
}
