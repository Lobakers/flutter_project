import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ContractApi {
  static Future<List<dynamic>> getContracts(BuildContext context) async {
    try {
      final response = await ApiService.get(context, Api.contract);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load contracts');
      }
    } catch (e) {
      debugPrint('ContractApi error: $e');
      throw Exception('Network error: $e');
    }
  }
}
