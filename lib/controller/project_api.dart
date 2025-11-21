import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ProjectApi {
  static Future<List<dynamic>> getProjects(BuildContext context) async {
    try {
      final response = await ApiService.get(context, Api.project);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load projects');
      }
    } catch (e) {
      debugPrint('ProjectApi error: $e');
      throw Exception('Network error: $e');
    }
  }
}
