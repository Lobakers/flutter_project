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
