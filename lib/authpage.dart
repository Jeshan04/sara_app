import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Replace with your actual paths
import 'package:pangea/data_collection/test_provisioning.dart';
import 'home_page.dart';
import 'loginpage.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 1. User NOT logged in
          if (!snapshot.hasData) {
            return const LoginScreen();
          }

          // 2. User IS logged in → Check sensor status
          return FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, prefSnapshot) {
              if (!prefSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final prefs = prefSnapshot.data!;
              final heelIp = prefs.getString('pangea_heel_ip');
              final foreIp = prefs.getString('pangea_forefoot_ip');

              // If sensors aren't paired, go to Provisioning
              if (heelIp == null || foreIp == null) {
                return const TestProvisioningScreen(title: "Pair Sensors");
              }

              // If sensors ARE paired, go straight to Baseline (Calibration)
              else {
                return const TestHomePage();
              }
            },
          );
        },
      ),
    );
  }
}