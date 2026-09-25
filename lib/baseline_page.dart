import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_page.dart';

class BaselinePage extends StatefulWidget {
  const BaselinePage({super.key});

  @override
  State<BaselinePage> createState() => _BaselinePageState();
}

class _BaselinePageState extends State<BaselinePage> {
  // Dual Connection State
  bool isHeelConnected = false;
  bool isForefootConnected = false;
  bool isResolving = true;

  String? _heelUrl;
  String? _forefootUrl;
  Timer? _reconnectTimer;
  bool _isCalibrating = false;

  @override
  void initState() {
    super.initState();
    _bootstrapDevices();
  }

  Future<void> _bootstrapDevices() async {
    setState(() => isResolving = true);
    final prefs = await SharedPreferences.getInstance();

    final hIp = prefs.getString('pangea_heel_ip');
    final fIp = prefs.getString('pangea_forefoot_ip');

    if (hIp == null || fIp == null) {
      setState(() => isResolving = false);
      return;
    }

    _heelUrl = "http://$hIp";
    _forefootUrl = "http://$fIp";

    _checkBothConnections();
    _reconnectTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _checkBothConnections());
  }

  Future<void> _checkBothConnections() async {
    try {
      // Current firmware has no /whoami — /data is both the liveness
      // check and the only route that exists.
      final responses = await Future.wait([
        http
            .get(Uri.parse("$_heelUrl/data"))
            .timeout(const Duration(seconds: 2)),
        http
            .get(Uri.parse("$_forefootUrl/data"))
            .timeout(const Duration(seconds: 2)),
      ]);

      if (mounted) {
        setState(() {
          isHeelConnected = responses[0].statusCode == 200;
          isForefootConnected = responses[1].statusCode == 200;
          isResolving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isHeelConnected = false;
          isForefootConnected = false;
          isResolving = false;
        });
      }
    }
  }

  // --- IMPROVED CALIBRATION LOGIC ---
  Future<void> _recordBaseline() async {
    setState(() => _isCalibrating = true);

    try {
      // 1. Fetch current raw frames from both sensors [cite: 202, 209]
      final responses = await Future.wait([
        http
            .get(Uri.parse("$_heelUrl/data"))
            .timeout(const Duration(seconds: 3)),
        http
            .get(Uri.parse("$_forefootUrl/data"))
            .timeout(const Duration(seconds: 3)),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final hData = jsonDecode(responses[0].body);
        final fData = jsonDecode(responses[1].body);
        final prefs = await SharedPreferences.getInstance();

        // Save accel bias offsets. Current firmware only reports x/y/z
        // accel — no gyro — so there's nothing to store for gx/gy/gz yet.
        await prefs.setDouble('base_hAx', (hData['x'] as num).toDouble());
        await prefs.setDouble('base_hAy', (hData['y'] as num).toDouble());
        await prefs.setDouble('base_hAz', (hData['z'] as num).toDouble());

        await prefs.setDouble('base_fAx', (fData['x'] as num).toDouble());
        await prefs.setDouble('base_fAy', (fData['y'] as num).toDouble());
        await prefs.setDouble('base_fAz', (fData['z'] as num).toDouble());

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dual-Sensor Baseline Set")),
        );

        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const TestPage()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error capturing baseline data")),
      );
    } finally {
      if (mounted) setState(() => _isCalibrating = false);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool allConnected = isHeelConnected && isForefootConnected;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text("Setup PliéSense",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "Position both sensors on your ankle. Stand perfectly still in a neutral position to calibrate.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),

              const Spacer(),
              Image.asset('lib/assets/images/sleeve.png',
                  height: MediaQuery.of(context).size.height * 0.3),
              const Spacer(),

              // Connection Status Monitors
              _connectionStatusRow("Heel Sensor", isHeelConnected),
              const SizedBox(height: 8),
              _connectionStatusRow("Forefoot Sensor", isForefootConnected),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: (allConnected && !_isCalibrating)
                      ? _recordBaseline
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: _isCalibrating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          allConnected
                              ? "Record Baseline"
                              : "Waiting for Sensors...",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionStatusRow(String label, bool connected) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
            radius: 4, backgroundColor: connected ? Colors.green : Colors.red),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: connected ? Colors.black : Colors.grey, fontSize: 13)),
      ],
    );
  }
}
