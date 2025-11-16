import 'dart:convert';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

class ApiService {
  static Future<http.Response> get(BuildContext context, String url) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    return await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'JWT $token',
      },
    );
  }

  static Future<http.Response> post(
    BuildContext context,
    String url,
    Map<String, dynamic> body,
  ) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    return await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'JWT $token',
      },
      body: jsonEncode(body),
    );
  }
}
