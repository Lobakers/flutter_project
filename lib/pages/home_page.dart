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
  String _currentAddress = "Search Location";
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // Directly get email from provider
    final email = auth.userInfo?['email'] ?? 'No email';
    final companyName = auth.userInfo?['companyName'] ?? 'No company name';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('beeWhere')),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          first_banner(email, companyName),
          timeInformation(),
          const SizedBox(height: 10),
          workLocationSelector(),
          const SizedBox(height: 10),
          locationDisplay(),
        ],
      ),
    );
  }

  Container first_banner(email, companyName) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background_login.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.account_circle, size: 80, color: Colors.white),
          const SizedBox(width: 30),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good Day!',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                email,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              Text(
                companyName,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget timeInformation() {
    return Container(
      padding: const EdgeInsets.all(15.0),
      margin: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clock in',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color.fromARGB(255, 64, 205, 137),
            ),
          ),
          Text(
            'You Haven\'t Clocked in Yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '09:00 AM',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              Text('14 November 2023'),
            ],
          ),
        ],
      ),
    );
  }

  Widget workLocationSelector() {
    final locations = ['Office', 'Site', 'Home', 'Others'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: locations.map((title) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget locationDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
      child: Row(
        children: [
          // Address display area
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: _isLoading
                    ? CircularProgressIndicator(strokeWidth: 2)
                    : Text(
                        _currentAddress,
                        style: TextStyle(color: Colors.black, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),

          const SizedBox(width: 15),

          // Refresh location button
          Container(
            decoration: BoxDecoration(
              color: BeeColor.fillIcon, // Using your theme color
              border: Border.all(color: Colors.black, width: 2.0),
              borderRadius: BorderRadius.circular(30.0),
            ),
            child: IconButton(
              icon: Icon(Icons.my_location),
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() {
                        _isLoading = true;
                      });
                      // Call your location function here
                      // await _getCurrentPosition();
                      setState(() {
                        _isLoading = false;
                      });
                    },
              color: Colors.black,
              iconSize: 24.0,
            ),
          ),
        ],
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
