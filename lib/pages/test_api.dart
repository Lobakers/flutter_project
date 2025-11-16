import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Replace with your actual token
  const token =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImlyZmFuQHplbi5jb20ubXkiLCJ1c2VySWQiOiI0NmEzYWFjMi0yMjFhLTExZWYtOTZhMC0yNzczZjYwZWNhNTEiLCJ0ZW5hbnRJZCI6IjQ3ZDM3YjgwLTA5MzktMTFlYi1hM2UxLTY5ZWQ4MWRlNDA4YyIsImlhdCI6MTc2MzEwMzE3MywiZXhwIjoxNzYzMTQ5OTczfQ.Bn3EpsErjGOwqV_FJeDlNkBUalekaVbeO2Terv_3WLU';

  // Your user-info endpoint
  const userInfoUrl = 'https://devamscore.beesuite.app/api/user-info';

  try {
    final response = await http.get(
      Uri.parse(userInfoUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'JWT $token', // <-- important!
      },
    );

    print('=== USER-INFO RESPONSE ===');
    print('Status code: ${response.statusCode}');
    print('Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('User info: $data');
    } else {
      print('Failed to get user info: ${response.body}');
    }
  } catch (e) {
    print('Error calling user-info API: $e');
  }
}
