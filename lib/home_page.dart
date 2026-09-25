import 'package:flutter/material.dart';

import 'baseline_page.dart';

class TestHomePage extends StatefulWidget {
  const TestHomePage({super.key});

  @override
  State<TestHomePage> createState() => _TestHomePageState();
}

class _TestHomePageState extends State<TestHomePage> {
  bool _isVisible = false;
  final String gifUrl =
      "https://gifdb.com/images/high/cute-pirouette-ballet-cartoon-ballerina-kbi9lt09n2lisazm.gif";

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isVisible = true);
    });
  }

  @override
  void didChangeDependencies() {
    precacheImage(NetworkImage(gifUrl), context);
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: Colors.white),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // --- 1. THE LARGE GIF (80% Height) ---
            AnimatedOpacity(
              opacity: _isVisible ? 0.6 : 0.0,
              duration: const Duration(seconds: 3),
              child: Image.network(
                gifUrl,
                height: screenHeight * 0.8, // 80% coverage
                width: double.infinity,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 1));
                },
              ),
            ),

            // --- 2. FLOATING TEXT LAYER (Top 25%) ---
            Positioned(
              top: screenHeight * 0.20,
              child: AnimatedOpacity(
                opacity: _isVisible ? 1.0 : 0.0,
                duration: const Duration(seconds: 2),
                child: Column(
                  children: [
                    Text(
                      "Hi, Sara!",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Text(
                      "Welcome",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 52,
                        fontWeight:
                            FontWeight.w900, // Thicker for premium contrast
                        letterSpacing: -2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- 3. FLOATING BUTTON LAYER (Bottom 75%) ---
            Positioned(
              top: screenHeight * 0.75,
              child: AnimatedOpacity(
                opacity: _isVisible ? 1.0 : 0.0,
                duration: const Duration(seconds: 3),
                child: _buildPremiumButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BaselinePage())),
      child: Container(
        width: 280,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white
              .withOpacity(0.9), // Slight transparency for classiness
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Let's set the baseline",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
