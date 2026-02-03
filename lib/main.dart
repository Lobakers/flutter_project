import 'package:beewhere/pages/history_page.dart';
import 'package:beewhere/pages/main_shell.dart';
import 'package:beewhere/pages/login_page.dart';
import 'package:beewhere/pages/profile_page.dart';
import 'package:beewhere/pages/report_page.dart';
import 'package:beewhere/pages/support_page.dart';
import 'package:beewhere/pages/splash_screen.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/attendance_provider.dart';
import 'package:beewhere/providers/clock_provider.dart';
import 'package:beewhere/services/connectivity_service.dart';
import 'package:beewhere/services/offline_database.dart';
import 'package:beewhere/services/pending_sync_service.dart';
import 'package:beewhere/services/sync_service.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logger service
  await LoggerService.init();

  // Initialize offline services
  await OfflineDatabase.init();
  await PendingSyncService.init();
  ConnectivityService.init();
  SyncService.init();

  // ✨ Initialize map tile caching for offline use
  try {
    // Initialize the caching backend
    await FMTCObjectBoxBackend().initialise();

    // Create the map store (only creates if doesn't exist)
    await FMTCStore('mapStore').manage.create(); // ✅ Changed from FMTC.instance

    debugPrint('✅ Map tile caching initialized');
  } catch (e) {
    // If store already exists, this will throw an error - that's OK
    debugPrint('ℹ️ Map caching note: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => ClockProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeeWhere',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const SplashScreen(), // Start with splash screen
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const MainShell(),
        '/history': (context) => const HistoryPage(),
        '/profile': (context) => const ProfilePage(),
        '/report': (context) => const ReportPage(),
        '/support': (context) => const SupportPage(),
      },
    );
  }
}
