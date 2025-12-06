import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ClientDetailApi {
  static Future<List<dynamic>> getClients(BuildContext context) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        final response = await ApiService.get(context, Api.client_detail);

        if (response.statusCode == 200) {
          final clients = jsonDecode(response.body) as List<dynamic>;

          // Cache the data for offline use
          await OfflineDatabase.saveClients(clients);

          debugPrint('✅ Fetched ${clients.length} clients from API and cached');
          return clients;
        } else {
          throw Exception('Failed to load clients');
        }
      } else {
        // OFFLINE: Return cached data
        final cachedClients = await OfflineDatabase.getClients();
        debugPrint(
          '📱 Loaded ${cachedClients.length} clients from offline cache',
        );
        return cachedClients;
      }
    } catch (e) {
      debugPrint('❌ Error in getClients: $e');

      // On error, try to return cached data as fallback
      try {
        final cachedClients = await OfflineDatabase.getClients();
        if (cachedClients.isNotEmpty) {
          debugPrint('⚠️ Using cached clients due to error');
          return cachedClients;
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached clients: $cacheError');
      }

      throw Exception('Network error: $e');
    }
  }
}
