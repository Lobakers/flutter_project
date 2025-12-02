import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:beewhere/routes/api.dart';

class LoginApi {
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse(Api.login),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        "email": email,
        "password": base64Encode(
          utf8.encode(password),
        ), // Base64 encode password
      }),
    );

    debugPrint('Login Response Status: ${response.statusCode}');
    debugPrint('Login Response Body: ${response.body}');

    try {
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {"success": true, "data": data};
      } else {
        return {
          "success": false,
          "message":
              data['message']?['message'] ??
              data['message'] ??
              'Login failed with status ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('Error decoding login response: $e');
      return {
        "success": false,
        "message":
            'Server error (${response.statusCode}): Invalid response format',
      };
    }
  }
}
