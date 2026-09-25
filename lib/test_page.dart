import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pangea/sensor_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ensure you have your SensorFrame model imported or defined here
// from Block 1 of your documentation

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  bool isConnected = false;
  String? _heelBaseUrl;
  String? _forefootBaseUrl;
  Timer? _updateTimer;

  // We store the most recent combined data in a SensorFrame
  SensorFrame? _currentFrame;

  @override
  void initState() {
    super.initState();
    _initDualDashboard();
  }

  Future<void> _initDualDashboard() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      final hIp = prefs.getString('pangea_heel_ip');
      final fIp = prefs.getString('pangea_forefoot_ip');

      if (hIp != null) _heelBaseUrl = "http://$hIp";
      if (fIp != null) _forefootBaseUrl = "http://$fIp";
    });

    // Refresh every 500ms for a "classier" live feel
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_heelBaseUrl != null && _forefootBaseUrl != null) {
        _fetchDualSensorData();
      }
    });
  }

  Future<void> _fetchDualSensorData() async {
    try {
      // Parallel requests ensure we get data from both sensors at the same time
      final responses = await Future.wait([
        http
            .get(Uri.parse("$_heelBaseUrl/data"))
            .timeout(const Duration(milliseconds: 400)),
        http
            .get(Uri.parse("$_forefootBaseUrl/data"))
            .timeout(const Duration(milliseconds: 400)),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final hData = jsonDecode(responses[0].body);
        final fData = jsonDecode(responses[1].body);

        if (!mounted) return;

        setState(() {
          isConnected = true;
          // Map raw JSON to the SensorFrame model. Current firmware only
          // reports accel (x/y/z) — no gyro.
          _currentFrame = SensorFrame(
            ts: DateTime.now().millisecondsSinceEpoch,
            hAx: (hData['x'] as num).toDouble(),
            hAy: (hData['y'] as num).toDouble(),
            hAz: (hData['z'] as num).toDouble(),
            fAx: (fData['x'] as num).toDouble(),
            fAy: (fData['y'] as num).toDouble(),
            fAz: (fData['z'] as num).toDouble(),
          );
        });
      }
    } catch (_) {
      if (mounted) setState(() => isConnected = false);
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text("Dual Sensor Live",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          Icon(Icons.circle,
              size: 12, color: isConnected ? Colors.green : Colors.red),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildSensorSection("HEEL SENSOR", [
              {
                'label': 'H-Accel X',
                'val': _currentFrame?.hAx ?? 0.0,
                'color': Colors.redAccent
              },
              {
                'label': 'H-Accel Y',
                'val': _currentFrame?.hAy ?? 0.0,
                'color': Colors.green
              },
              {
                'label': 'H-Accel Z',
                'val': _currentFrame?.hAz ?? 0.0,
                'color': Colors.blueAccent
              },
            ]),
            const SizedBox(height: 24),
            _buildSensorSection("FOREFOOT SENSOR", [
              {
                'label': 'F-Accel X',
                'val': _currentFrame?.fAx ?? 0.0,
                'color': Colors.redAccent
              },
              {
                'label': 'F-Accel Y',
                'val': _currentFrame?.fAy ?? 0.0,
                'color': Colors.green
              },
              {
                'label': 'F-Accel Z',
                'val': _currentFrame?.fAz ?? 0.0,
                'color': Colors.blueAccent
              },
            ]),
            const SizedBox(height: 30),
            Text(
              isConnected
                  ? "System Synchronized"
                  : "Reconnecting to sensors...",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorSection(String title, List<Map<String, dynamic>> axes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12)),
        ),
        ...axes
            .map((axis) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 15,
                            offset: const Offset(0, 5))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(axis['label'],
                            style: TextStyle(
                                color: axis['color'],
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text(
                          (axis['val'] as double).toStringAsFixed(3),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ],
    );
  }
}
