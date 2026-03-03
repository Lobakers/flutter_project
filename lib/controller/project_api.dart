import 'dart:convert';
import 'package:beewhere/controller/api_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:beewhere/routes/api.dart';

class ProjectApi {
  static Future<List<dynamic>> getProjects(BuildContext context) async {
    try {
      // Check if online
      final isOnline = await ConnectivityService.checkConnectivity();

      if (isOnline) {
        // ONLINE: Fetch from API
        final response = await ApiService.get(context, Api.project);

        if (response.statusCode == 200) {
          final projects = jsonDecode(response.body) as List<dynamic>;

          // Cache the data for offline use
          await OfflineDatabase.saveProjects(projects);

          debugPrint(
            '✅ Fetched ${projects.length} projects from API and cached',
          );
          return projects;
        } else {
          throw Exception('Failed to load projects');
        }
      } else {
        // OFFLINE: Return cached data
        final cachedProjects = await OfflineDatabase.getProjects();
        debugPrint(
          '📱 Loaded ${cachedProjects.length} projects from offline cache',
        );
        return cachedProjects;
      }
    } catch (e) {
      debugPrint('❌ ProjectApi error: $e');

      // On error, try to return cached data as fallback
      try {
        final cachedProjects = await OfflineDatabase.getProjects();
        if (cachedProjects.isNotEmpty) {
          debugPrint('⚠️ Using cached projects due to error');
          return cachedProjects;
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to get cached projects: $cacheError');
      }

      // ✅ FIX: Return empty list instead of throwing.
      debugPrint('⚠️ No projects available (offline + no cache). Returning [].');
      return [];
    }
  }
}
