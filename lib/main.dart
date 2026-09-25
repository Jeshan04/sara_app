import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pangea/data_collection/test_provisioning.dart';
import 'package:pangea/home_page.dart';
// Import your actual pages here
import 'package:pangea/loginpage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();

  // Hardware reset flags for testing
  await prefs.setBool('session_provisioned', false);
  await prefs.setBool('electrode_chosen', false);
  await prefs.setBool('baseline_complete', false);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Sara\'s App',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: ThemeMode.system,

      // Points directly to the logic wrapper instead of AppRouter
      home: const RootWrapper(),

      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Positioned(
              bottom: 100,
              right: 20,
              child: FloatingActionButton(
                heroTag: 'masterSkipBtn',
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: () => _testForceNext(),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _testForceNext() async {
    final prefs = await SharedPreferences.getInstance();

    if (!(prefs.getBool('onboarding_complete') ?? false)) {
      await prefs.setBool('onboarding_complete', true);
    } else if (!(prefs.getBool('session_provisioned') ?? false)) {
      await prefs.setBool('session_provisioned', true);
    } else if (!(prefs.getBool('electrode_chosen') ?? false)) {
      await prefs.setBool('electrode_chosen', true);
    }

    // Since AppRouter is gone, we push the RootWrapper to re-calculate state
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootWrapper()),
      (route) => false,
    );
  }
}

/// This replaces the AppRouter logic
class RootWrapper extends StatelessWidget {
  const RootWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SharedPreferences.getInstance(),
      builder: (context, AsyncSnapshot<SharedPreferences> snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final prefs = snapshot.data!;
        final user = FirebaseAuth.instance.currentUser;

        // 1. Check Auth
        if (user == null) return const LoginScreen();

        // 2. Check Onboarding/Wifi
        if (!(prefs.getBool('session_provisioned') ?? false)) {
          return const TestProvisioningScreen(
            title: 'wifi',
          );
        }

        // 3. Default to Profile Setup
        return const TestHomePage();
      },
    );
  }
}
