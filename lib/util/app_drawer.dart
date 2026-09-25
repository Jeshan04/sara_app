import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pangea/app_router.dart';
import 'package:pangea/util/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_collection/test_provisioning.dart';

class AppDrawer extends StatelessWidget {
  final bool isConnected;
  final VoidCallback? onReconnect;

  const AppDrawer({super.key, this.isConnected = false, this.onReconnect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Drawer(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: primaryColor.withOpacity(0.05)),
            child: Center(
              child: Image.asset(
                isDark
                    ? 'lib/assets/images/logo1.png'
                    : 'lib/assets/images/logo2.png',
                width: 80,
              ),
            ),
          ),

          // --- WIFI STATUS SECTION ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isConnected
                    ? Colors.green.withOpacity(0.1)
                    : Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isConnected ? Colors.green : Colors.redAccent,
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isConnected ? Icons.wifi : Icons.wifi_off,
                        color: isConnected ? Colors.green : Colors.redAccent,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isConnected ? "Device Connected" : "Connection Lost",
                        style: TextStyle(
                          color: isConnected ? Colors.green : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (!isConnected) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('session_provisioned', false);
                            // Also clear the IP to force a fresh scan
                            await prefs.remove('pangea_device_ip');
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const TestProvisioningScreen(
                                          title: 'wifi',
                                        )),
                                (route) => false,
                              );
                            }
                          },
                          child: const Text("Change WiFi"),
                        ),
                      ],
                    )
                  ]
                ],
              ),
            ),
          ),

          // --- NEW: DATA COLLECTION LOOP BUTTON ---
          ListTile(
            leading: Icon(Icons.person_add_alt_1, color: primaryColor),
            title: Text('New Test Profile',
                style: TextStyle(
                    color: primaryColor, fontWeight: FontWeight.w600)),
            subtitle: const Text('Reset profile and baseline',
                style: TextStyle(fontSize: 11)),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();

              // Reset the flags so AppRouter takes you back to ProfileSetupPage
              await prefs.setBool('test_profile_complete', false);
              await prefs.setBool('baseline_complete', false);

              if (!context.mounted) return;

              // Restart the flow
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AppRouter()),
                (route) => false,
              );
            },
          ),

          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();

              final prefs = await SharedPreferences.getInstance();
              // Full reset on logout
              await prefs.setBool('session_provisioned', false);
              await prefs.setBool('electrode_chosen', false);
              await prefs.setBool('baseline_complete', false);
              await prefs.setBool('test_profile_complete', false);
              await prefs.remove('pangea_device_ip');

              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AppRouter()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
