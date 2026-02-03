import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/providers/clock_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Wait for a brief moment to show splash
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Load stored authentication
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isLoggedIn = await auth.loadStoredAuth();

    if (!mounted) return;

    if (isLoggedIn) {
      // Load initial data for clock provider
      final clock = Provider.of<ClockProvider>(context, listen: false);
      // Wait for data to load before proceeding
      await clock.loadDropdownData(context);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background_login.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/beeWhere.png', width: 150, height: 150),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              'BeeWhere',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
