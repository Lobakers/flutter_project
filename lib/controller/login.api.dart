import 'dart:convert';
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

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return {"success": true, "data": data};
    } else {
      return {
        "success": false,
        "message": data['message']?['message'] ?? 'Login failed',
      };
    }
  }
}
