import 'package:flutter/material.dart';
import 'package:pangea/loginpage.dart';
import 'package:pangea/sign_up.dart';
import 'package:pangea/util/app_colors.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final primaryText =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  isDark
                      ? 'lib/assets/images/logo1.png'
                      : 'lib/assets/images/logo2.png',
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 40),
                Text(
                  'Welcome to Sara\'s App',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Neural health, made simple',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 48),

                // 1. Primary: Sign In
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text('Sign in',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Secondary: Create Account
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: accent.withOpacity(0.5), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SignUpPage())),
                    child: Text('Create account',
                        style: TextStyle(
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                ),

                const SizedBox(height: 32),

                // 3. UPDATED ROUTE: Collect Test Data
                // SizedBox(
                //   width: 200,
                //   height: 44,
                //   child: TextButton.icon(
                //     onPressed: () => Navigator.push(
                //       context,
                //       MaterialPageRoute(
                //           builder: (_) => const TestProvisioningScreen(
                //               title: 'Quick Test')),
                //     ),
                //     style: TextButton.styleFrom(
                //       backgroundColor: accent.withOpacity(0.08),
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(20),
                //       ),
                //     ),
                //     icon: Icon(Icons.science_outlined,
                //         size: 18, color: accent.withOpacity(0.7)),
                //     label: Text(
                //       'Collect Test Data',
                //       style: TextStyle(
                //         color: accent.withOpacity(0.8),
                //         fontSize: 13,
                //         fontWeight: FontWeight.w500,
                //         letterSpacing: 0.5,
                //       ),
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
