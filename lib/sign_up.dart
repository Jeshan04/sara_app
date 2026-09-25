import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pangea/data_collection/test_provisioning.dart';
import 'package:pangea/loginpage.dart';
import 'package:pangea/util/app_colors.dart';
import 'package:pangea/util/mytextfield.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // Controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  // Firebase Instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Form Key
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateName(String? value, {required String fieldName}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName is required';
    if (v.length < 2) return '$fieldName must be at least 2 characters';
    final nameRegex = RegExp(r"^[a-zA-Z][a-zA-Z\s'\-]*$");
    if (!nameRegex.hasMatch(v)) return 'Enter a valid $fieldName';
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = (value ?? '');
    if (v.trim().isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(v);
    final hasLower = RegExp(r'[a-z]').hasMatch(v);
    final hasDigit = RegExp(r'\d').hasMatch(v);
    final hasSpecial =
        RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=/\\\[\]~`]').hasMatch(v);

    if (!hasUpper) return 'Add at least 1 uppercase letter';
    if (!hasLower) return 'Add at least 1 lowercase letter';
    if (!hasDigit) return 'Add at least 1 number';
    if (!hasSpecial) return 'Add at least 1 special character';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = (value ?? '');
    if (v.trim().isEmpty) return 'Confirm your password';
    if (v != passwordController.text) return 'Passwords do not match';
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signUp() async {
    if (_isLoading) return; // prevent double submits

    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;

    setState(() => _isLoading = true);

    try {
      // Create user in Firebase Authentication (auto logs in)
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'Could not create user. Please try again.',
        );
      }

      // Save additional user info to Firestore
      await _firestore.collection('users').doc(uid).set({
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'email': emailController.text.trim().toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark onboarding not complete and go straight to onboarding
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', false);

      if (!mounted) return;

      _showSnack('Account created!');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => const TestProvisioningScreen(title: "wifi")),
      );
    } on FirebaseAuthException catch (e) {
      // Helpful messages
      final msg = switch (e.code) {
        'email-already-in-use' => 'That email is already in use.',
        'invalid-email' => 'That email address is invalid.',
        'weak-password' => 'That password is too weak.',
        'operation-not-allowed' =>
          'Email/password sign-in is disabled in Firebase.',
        _ => e.message ?? 'An unknown auth error occurred.',
      };
      _showSnack(msg);
    } catch (e) {
      _showSnack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // THEME-AWARE LOGO IMPLEMENTATION
              Image.asset(
                isDark
                    ? 'lib/assets/images/logo1.png'
                    : 'lib/assets/images/logo2.png',
                width: 120,
                height: 120,
              ),

              const SizedBox(height: 40),
              Text(
                'Sign up',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 30),

              // ✅ Form remains the same
              Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    MyTextField(
                      hint: 'First Name',
                      obscureText: false,
                      controller: firstNameController,
                      icon: const Icon(Icons.person),
                      validator: (v) =>
                          _validateName(v, fieldName: 'First name'),
                    ),
                    const SizedBox(height: 16),
                    MyTextField(
                      hint: 'Last Name',
                      obscureText: false,
                      controller: lastNameController,
                      icon: const Icon(Icons.person),
                      validator: (v) =>
                          _validateName(v, fieldName: 'Last name'),
                    ),
                    const SizedBox(height: 16),
                    MyTextField(
                      hint: 'Email',
                      obscureText: false,
                      controller: emailController,
                      icon: const Icon(Icons.email),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    MyTextField(
                      hint: 'Password',
                      obscureText: true,
                      controller: passwordController,
                      icon: const Icon(Icons.lock),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),
                    MyTextField(
                      hint: 'Confirm Password',
                      obscureText: true,
                      controller: confirmPasswordController,
                      icon: const Icon(Icons.lock),
                      validator: _validateConfirmPassword,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Sign up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // You said: skip login after signup, so removed navigation to LoginScreen.
              // If you still want a "Already have an account? Sign in" link, add it back.

              const SizedBox(height: 8),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Sign in',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.lightPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
