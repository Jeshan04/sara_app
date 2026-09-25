import 'dart:async';

import 'package:flutter/material.dart';

import 'plie_sense_core.dart'; // From Block 1 [cite: 42]

class PlieSenseProvider extends ChangeNotifier {
  final PlieSensePipeline _pipeline = PlieSensePipeline(); // From Block 11
  final UdpReceiver _receiver = UdpReceiver(port: 5005); // From Block 2

  RiskEvent? lastEvent;
  double currentAnkleAngle = 0.0;

  PlieSenseProvider() {
    // 1. Listen to raw frames and feed them to the pipeline [cite: 706]
    _receiver.frames.listen((frame) {
      _pipeline.ingest(frame);

      // 2. Extract live angle for the UI Gauge [cite: 263]
      currentAnkleAngle = _pipeline.currentAnkleAngle;
      notifyListeners();
    });

    // 3. Listen for detected moves (Sauté, Pirouette, etc.) [cite: 708]
    _pipeline.riskEvents.stream.listen((event) {
      lastEvent = event;
      notifyListeners();
    });
  }

  void start() => _receiver.start(); // [cite: 176]
  void stop() => _receiver.stop(); // [cite: 192]

  bool get isCalibrated => _pipeline.isCalibrated; // [cite: 675]
  int get safetyScore => _pipeline.currentScore; // [cite: 674]
}
