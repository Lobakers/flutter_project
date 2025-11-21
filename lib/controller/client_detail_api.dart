import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ClientDetailApi {
  static Future<List<dynamic>> getClients(BuildContext context) async {
    try {
      final response = await ApiService.get(context, Api.client_detail);

      if (response.statusCode == 200) {
        return jsonDecode(
          response.body,
        ); // Just return the client list directly
      } else {
        throw Exception('Failed to load clients');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
