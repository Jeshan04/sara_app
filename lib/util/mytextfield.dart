import 'package:flutter/material.dart';

import 'app_colors.dart';

class MyTextField extends StatelessWidget {
  final String hint;
  final bool obscureText;
  final TextEditingController controller;
  final Icon icon;
  final Widget? suffixIcon; // 1. Added suffixIcon property
  final String? Function(String?)? validator;
  final TextInputType keyboardType;

  const MyTextField({
    super.key,
    required this.hint,
    required this.obscureText,
    required this.controller,
    required this.icon,
    this.suffixIcon, // 2. Added to constructor
    this.validator,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      decoration: InputDecoration(
        prefixIcon: icon,
        suffixIcon: suffixIcon, // 3. Passed to decoration
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
        ),
        // ... rest of your existing styling
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
          ),
        ),
      ),
    );
  }
}
