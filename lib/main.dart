import 'package:beewhere/pages/history_page.dart';
import 'package:beewhere/pages/home_page.dart';
import 'package:beewhere/pages/login_page.dart';
import 'package:beewhere/pages/profile_page.dart';
import 'package:beewhere/providers/attendance_provider.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logger service
  await LoggerService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
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
      title: 'beeWhere',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(), // Start with splash screen
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/history': (context) => const HistoryPage(),
        '/profile': (context) => const ProfilePage(),
      },
    );
  }
}

/// Splash screen that checks for stored credentials
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Try to load stored credentials
    final hasStoredAuth = await authProvider.loadStoredAuth();

    // Wait a bit for splash screen visibility
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // Navigate based on authentication status
    if (hasStoredAuth) {
      // User has valid stored credentials, go to home
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      // No stored credentials, go to login
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background_login.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/beeWhere.png', width: 150),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'Loading...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
