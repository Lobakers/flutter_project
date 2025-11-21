import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class CoordinateApi {
  /// Converts lat/long to formatted address using backend API
  static Future<String> getAddressFromCoordinates(
    BuildContext context,
    double latitude,
    double longitude,
  ) async {
    try {
      // Format: "lat,long"
      final input = "$latitude,$longitude";
      final url = "${Api.coordinate}$input";

      final response = await ApiService.get(context, url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract formatted address from response
        if (data['results'] != null && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'] ?? "Unknown location";
        }
        return "Address not found";
      } else {
        throw Exception('Failed to get address');
      }
    } catch (e) {
      debugPrint('CoordinateApi error: $e');
      // Return coordinates as fallback
      return "${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}";
    }
  }
}
