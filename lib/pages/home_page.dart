import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/theme/color_theme.dart';
import 'package:beewhere/widgets/drawer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // Directly get email from provider
    final email = auth.userInfo?['email'] ?? 'No email';
    final companyName = auth.userInfo?['companyName'] ?? 'No company name';

    return Scaffold(
      appBar: AppBar(title: const Text('beeWhere')),
      drawer: const AppDrawer(),
      body: Center(
        child: Container(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.account_circle, size: 60, color: BeeColor.buttonColor),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good Day!', style: TextStyle(fontSize: 14)),
                  Text(email, style: const TextStyle(fontSize: 14)),
                  Text(companyName, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void logout(BuildContext context, AuthProvider auth) {
    auth.logout(); // clear token & user info
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }
}
