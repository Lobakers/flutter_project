import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ContractApi {
  static Future<List<dynamic>> getContracts(BuildContext context) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        final response = await ApiService.get(context, Api.contract);

        if (response.statusCode == 200) {
          final contracts = jsonDecode(response.body) as List<dynamic>;

          // Cache the data for offline use
          await OfflineDatabase.saveContracts(contracts);

          debugPrint(
            '✅ Fetched ${contracts.length} contracts from API and cached',
          );
          return contracts;
        } else {
          throw Exception('Failed to load contracts');
        }
      } else {
        // OFFLINE: Return cached data
        final cachedContracts = await OfflineDatabase.getContracts();
        debugPrint(
          '📱 Loaded ${cachedContracts.length} contracts from offline cache',
        );
        return cachedContracts;
      }
    } catch (e) {
      debugPrint('❌ ContractApi error: $e');

      // On error, try to return cached data as fallback
      try {
        final cachedContracts = await OfflineDatabase.getContracts();
        if (cachedContracts.isNotEmpty) {
          debugPrint('⚠️ Using cached contracts due to error');
          return cachedContracts;
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached contracts: $cacheError');
      }

      throw Exception('Network error: $e');
    }
  }
}
