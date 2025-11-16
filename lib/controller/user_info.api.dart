import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class UserInfoApi {
  static Future<Map<String, dynamic>> getUserInfo(BuildContext context) async {
    final response = await ApiService.get(context, Api.user_info);

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {"success": true, "data": data};
    } else {
      return {"success": false, "message": data['message'] ?? "Failed"};
    }
  }
}
