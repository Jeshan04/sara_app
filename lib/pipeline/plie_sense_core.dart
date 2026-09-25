// =============================================================================
// PliéSense — Ballet Ankle Twist Detection System
// Dart implementation — Flutter-ready
// Blocks:
//   1. Data models
//   2. UDP receiver (dart:io)
//   3. Sensor calibrator
//   4. Low-pass filter + ankle angle integrator
//   5. Feature extractor
//   6. Move segmenter
//   7. Move classifier
//   8. Risk evaluator
//   9. Session scorer
//  10. Coaching feedback engine
//  11. Main pipeline
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 1: DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Raw sensor frame from one UDP packet (both MPUs).
class SensorFrame {
  final int ts; // sample index from ESP32
  // Heel MPU (0x68)
  final double hAx, hAy, hAz; // accel g
  final double hGx, hGy, hGz; // gyro °/s
  // Forefoot MPU (0x69)
  final double fAx, fAy, fAz;
  final double fGx, fGy, fGz;

  const SensorFrame({
    required this.ts,
    required this.hAx,
    required this.hAy,
    required this.hAz,
    required this.hGx,
    required this.hGy,
    required this.hGz,
    required this.fAx,
    required this.fAy,
    required this.fAz,
    required this.fGx,
    required this.fGy,
    required this.fGz,
  });

  /// Parse a 52-byte big-endian struct: 1×uint32 + 12×float32
  factory SensorFrame.fromBytes(Uint8List bytes) {
    final bd = bytes.buffer.asByteData();
    int o = 0;
    int ts = bd.getUint32(o, Endian.big);
    o += 4;
    double hAx = bd.getFloat32(o, Endian.big);
    o += 4;
    double hAy = bd.getFloat32(o, Endian.big);
    o += 4;
    double hAz = bd.getFloat32(o, Endian.big);
    o += 4;
    double hGx = bd.getFloat32(o, Endian.big);
    o += 4;
    double hGy = bd.getFloat32(o, Endian.big);
    o += 4;
    double hGz = bd.getFloat32(o, Endian.big);
    o += 4;
    double fAx = bd.getFloat32(o, Endian.big);
    o += 4;
    double fAy = bd.getFloat32(o, Endian.big);
    o += 4;
    double fAz = bd.getFloat32(o, Endian.big);
    o += 4;
    double fGx = bd.getFloat32(o, Endian.big);
    o += 4;
    double fGy = bd.getFloat32(o, Endian.big);
    o += 4;
    double fGz = bd.getFloat32(o, Endian.big);
    return SensorFrame(
      ts: ts,
      hAx: hAx,
      hAy: hAy,
      hAz: hAz,
      hGx: hGx,
      hGy: hGy,
      hGz: hGz,
      fAx: fAx,
      fAy: fAy,
      fAz: fAz,
      fGx: fGx,
      fGy: fGy,
      fGz: fGz,
    );
  }

  SensorFrame copyWith({
    double? hAx,
    double? hAy,
    double? hAz,
    double? hGx,
    double? hGy,
    double? hGz,
    double? fAx,
    double? fAy,
    double? fAz,
    double? fGx,
    double? fGy,
    double? fGz,
  }) =>
      SensorFrame(
        ts: ts,
        hAx: hAx ?? this.hAx,
        hAy: hAy ?? this.hAy,
        hAz: hAz ?? this.hAz,
        hGx: hGx ?? this.hGx,
        hGy: hGy ?? this.hGy,
        hGz: hGz ?? this.hGz,
        fAx: fAx ?? this.fAx,
        fAy: fAy ?? this.fAy,
        fAz: fAz ?? this.fAz,
        fGx: fGx ?? this.fGx,
        fGy: fGy ?? this.fGy,
        fGz: fGz ?? this.fGz,
      );
}

enum AlertLevel { safe, warning, danger }

enum MoveType { saute, grandBattement, releve, pirouette, grandPlie, unknown }

extension MoveTypeLabel on MoveType {
  String get label => switch (this) {
        MoveType.saute => 'Sauté',
        MoveType.grandBattement => 'Grand battement',
        MoveType.releve => 'Relevé',
        MoveType.pirouette => 'Pirouette',
        MoveType.grandPlie => 'Grand plié',
        MoveType.unknown => 'Unknown',
      };
}

class MoveFeatures {
  final double maxInversion;
  final double minEversion;
  final double peakAbsAngle;
  final double angleRange;
  final double maxRollRate;
  final double meanRollRate;
  final double peakHeelImpact;
  final double peakForeImpact;
  final double lateralHeelPeak;
  final double loadRatio;
  final double totalRotation;
  final double asymmetry;
  final bool isRising;
  final int durationFrames;

  const MoveFeatures({
    required this.maxInversion,
    required this.minEversion,
    required this.peakAbsAngle,
    required this.angleRange,
    required this.maxRollRate,
    required this.meanRollRate,
    required this.peakHeelImpact,
    required this.peakForeImpact,
    required this.lateralHeelPeak,
    required this.loadRatio,
    required this.totalRotation,
    required this.asymmetry,
    required this.isRising,
    required this.durationFrames,
  });
}

class RiskEvent {
  final MoveType move;
  final double riskScore; // 0–100
  final AlertLevel alert;
  final List<String> flags;
  final MoveFeatures features;
  final DateTime timestamp;

  const RiskEvent({
    required this.move,
    required this.riskScore,
    required this.alert,
    required this.flags,
    required this.features,
    required this.timestamp,
  });
}

class SessionSummary {
  final int sessionScore;
  final double durationSec;
  final int totalMoves;
  final int dangerCount;
  final int warningCount;
  final Map<MoveType, int> moveCounts;
  final Map<MoveType, double> moveAvgRisk;
  final double peakRollRate;
  final double peakAngle;
  final MoveType worstMove;
  final List<String> coaching;

  const SessionSummary({
    required this.sessionScore,
    required this.durationSec,
    required this.totalMoves,
    required this.dangerCount,
    required this.warningCount,
    required this.moveCounts,
    required this.moveAvgRisk,
    required this.peakRollRate,
    required this.peakAngle,
    required this.worstMove,
    required this.coaching,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 2: UDP RECEIVER
// ─────────────────────────────────────────────────────────────────────────────

class HttpReceiver {
  final String heelIp;
  final String foreIp;
  final StreamController<SensorFrame> _controller =
      StreamController<SensorFrame>.broadcast();
  Timer? _timer;

  HttpReceiver({required this.heelIp, required this.foreIp});

  Stream<SensorFrame> get frames => _controller.stream;

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 10), (t) async {
      try {
        final res = await Future.wait([
          http
              .get(Uri.parse("http://$heelIp/data"))
              .timeout(const Duration(milliseconds: 50)),
          http
              .get(Uri.parse("http://$foreIp/data"))
              .timeout(const Duration(milliseconds: 50)),
        ]);
        final h = jsonDecode(res[0].body);
        final f = jsonDecode(res[1].body);
        _controller.add(SensorFrame(
          ts: DateTime.now().millisecondsSinceEpoch,
          hAx: h['ax'],
          hAy: h['ay'],
          hAz: h['az'],
          hGx: h['gx'],
          hGy: h['gy'],
          hGz: h['gz'],
          fAx: f['ax'],
          fAy: f['ay'],
          fAz: f['az'],
          fGx: f['gx'],
          fGy: f['gy'],
          fGz: f['gz'],
        ));
      } catch (_) {}
    });
  }

  void stop() => _timer?.cancel();
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 3: SENSOR CALIBRATOR
// ─────────────────────────────────────────────────────────────────────────────

class SensorCalibrator {
  final int nSamples;
  final List<SensorFrame> _buf = [];

  // Bias offsets
  double _hAxB = 0, _hAyB = 0, _hAzB = 0, _hGxB = 0, _hGyB = 0, _hGzB = 0;
  double _fAxB = 0, _fAyB = 0, _fAzB = 0, _fGxB = 0, _fGyB = 0, _fGzB = 0;

  bool get isCalibrated => _buf.length >= nSamples;

  SensorCalibrator({this.nSamples = 200});

  /// Feed frames until isCalibrated == true.
  void feed(SensorFrame f) {
    if (isCalibrated) return;
    _buf.add(f);
    if (_buf.length == nSamples) _computeBias();
  }

  void _computeBias() {
    double avg(List<double> vals) => vals.reduce((a, b) => a + b) / vals.length;

    _hAxB = avg(_buf.map((f) => f.hAx).toList());
    _hAyB = avg(_buf.map((f) => f.hAy).toList());
    _hAzB = avg(_buf.map((f) => f.hAz).toList()) - 1.0; // remove gravity
    _hGxB = avg(_buf.map((f) => f.hGx).toList());
    _hGyB = avg(_buf.map((f) => f.hGy).toList());
    _hGzB = avg(_buf.map((f) => f.hGz).toList());

    _fAxB = avg(_buf.map((f) => f.fAx).toList());
    _fAyB = avg(_buf.map((f) => f.fAy).toList());
    _fAzB = avg(_buf.map((f) => f.fAz).toList()) - 1.0;
    _fGxB = avg(_buf.map((f) => f.fGx).toList());
    _fGyB = avg(_buf.map((f) => f.fGy).toList());
    _fGzB = avg(_buf.map((f) => f.fGz).toList());

    print('[Calibrator] Done. Heel biases: '
        'ax=${_hAxB.toStringAsFixed(4)}, az=${_hAzB.toStringAsFixed(4)}');
  }

  SensorFrame apply(SensorFrame f) => f.copyWith(
        hAx: f.hAx - _hAxB,
        hAy: f.hAy - _hAyB,
        hAz: f.hAz - _hAzB,
        hGx: f.hGx - _hGxB,
        hGy: f.hGy - _hGyB,
        hGz: f.hGz - _hGzB,
        fAx: f.fAx - _fAxB,
        fAy: f.fAy - _fAyB,
        fAz: f.fAz - _fAzB,
        fGx: f.fGx - _fGxB,
        fGy: f.fGy - _fGyB,
        fGz: f.fGz - _fGzB,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 4: LOW-PASS FILTER + ANKLE ANGLE INTEGRATOR
// ─────────────────────────────────────────────────────────────────────────────

class LowPassFilter {
  final double alpha; // 0 = freeze, 1 = no smoothing
  SensorFrame? _state;

  LowPassFilter({this.alpha = 0.3});

  SensorFrame process(SensorFrame f) {
    if (_state == null) {
      _state = f;
      return f;
    }
    final s = _state!;
    double lp(double n, double p) => alpha * n + (1 - alpha) * p;
    _state = f.copyWith(
      hAx: lp(f.hAx, s.hAx),
      hAy: lp(f.hAy, s.hAy),
      hAz: lp(f.hAz, s.hAz),
      hGx: lp(f.hGx, s.hGx),
      hGy: lp(f.hGy, s.hGy),
      hGz: lp(f.hGz, s.hGz),
      fAx: lp(f.fAx, s.fAx),
      fAy: lp(f.fAy, s.fAy),
      fAz: lp(f.fAz, s.fAz),
      fGx: lp(f.fGx, s.fGx),
      fGy: lp(f.fGy, s.fGy),
      fGz: lp(f.fGz, s.fGz),
    );
    return _state!;
  }
}

class AnkleAngleIntegrator {
  static const double dt = 0.01; // 100 Hz
  static const double _rad2deg = 180 / math.pi;

  double angle = 0.0; // + = inversion, - = eversion

  /// Returns updated ankle angle in degrees.
  double update(SensorFrame f) {
    final gyroRate = f.fGz;
    final accelAngle = math.atan2(
          f.fAx,
          math.sqrt(f.fAy * f.fAy + f.fAz * f.fAz),
        ) *
        _rad2deg;
    angle = 0.98 * (angle + gyroRate * dt) + 0.02 * accelAngle;
    return angle;
  }

  void reset() => angle = 0.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 5: FEATURE EXTRACTOR
// ─────────────────────────────────────────────────────────────────────────────

class FeatureExtractor {
  static MoveFeatures extract(
    List<SensorFrame> window,
    List<double> angles,
  ) {
    assert(window.isNotEmpty && angles.length == window.length);
    final n = window.length;

    double maxOf(List<double> v) => v.reduce(math.max);
    double minOf(List<double> v) => v.reduce(math.min);
    double absMax(List<double> v) => maxOf(v.map((x) => x.abs()).toList());
    double rms(List<double> v) {
      final sum = v.fold(0.0, (a, b) => a + b * b);
      return math.sqrt(sum / v.length);
    }

    final hAz = window.map((f) => f.hAz).toList();
    final fAz = window.map((f) => f.fAz).toList();
    final hAx = window.map((f) => f.hAx).toList();
    final fAx = window.map((f) => f.fAx).toList();
    final fGz = window.map((f) => f.fGz).toList();

    // Angle features
    final maxInversion = maxOf(angles);
    final minEversion = minOf(angles);
    final peakAbsAngle = math.max(maxInversion.abs(), minEversion.abs());

    // Roll rate
    final maxRollRate = absMax(fGz);
    final meanRollRate = fGz.map((v) => v.abs()).reduce((a, b) => a + b) / n;

    // Impact
    final peakHeelImpact = absMax(hAz);
    final peakForeImpact = absMax(fAz);
    final lateralHeelPeak = absMax(hAx);

    // Load ratio: lateral / vertical
    final vertRms = rms([...hAz, ...fAz]);
    final latRms = rms([...hAx, ...fAx]);
    final loadRatio = latRms / (vertRms + 1e-6);

    // Total rotation (trapezoid integration)
    double totalRotation = 0;
    for (int i = 1; i < n; i++) {
      totalRotation +=
          (fGz[i].abs() + fGz[i - 1].abs()) * 0.5 * AnkleAngleIntegrator.dt;
    }

    // Asymmetry: heel vs forefoot vertical
    final asymmetry = (peakHeelImpact - peakForeImpact).abs() /
        (peakHeelImpact + peakForeImpact + 1e-6);

    // Rise detection: linear trend on each sensor
    double linTrend(List<double> v) {
      final x = (n - 1) / 2.0;
      final y = v.reduce((a, b) => a + b) / n;
      double num = 0, den = 0;
      for (int i = 0; i < n; i++) {
        num += (i - x) * (v[i] - y);
        den += (i - x) * (i - x);
      }
      return den == 0 ? 0 : num / den;
    }

    final heelTrend = linTrend(hAz);
    final foreTrend = linTrend(fAz);
    final isRising = foreTrend > 0.01 && heelTrend < -0.01;

    return MoveFeatures(
      maxInversion: maxInversion,
      minEversion: minEversion,
      peakAbsAngle: peakAbsAngle,
      angleRange: maxInversion - minEversion,
      maxRollRate: maxRollRate,
      meanRollRate: meanRollRate,
      peakHeelImpact: peakHeelImpact,
      peakForeImpact: peakForeImpact,
      lateralHeelPeak: lateralHeelPeak,
      loadRatio: loadRatio,
      totalRotation: totalRotation,
      asymmetry: asymmetry,
      isRising: isRising,
      durationFrames: n,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 6: MOVE SEGMENTER
// ─────────────────────────────────────────────────────────────────────────────

typedef MoveCallback = void Function(
    List<SensorFrame> window, List<double> angles);

class MoveSegmenter {
  static const double onsetThreshold = 1.4;
  static const double offsetThreshold = 1.1;
  static const int quietFrames = 30;
  static const int minWindow = 20;
  static const int maxWindow = 500;

  final MoveCallback onMoveComplete;
  final AnkleAngleIntegrator _integrator = AnkleAngleIntegrator();

  bool _active = false;
  final List<SensorFrame> _frameBuf = [];
  final List<double> _angleBuf = [];
  int _quietCount = 0;

  MoveSegmenter({required this.onMoveComplete});

  void push(SensorFrame frame) {
    final angle = _integrator.update(frame);
    final hMag = math.sqrt(
      frame.hAx * frame.hAx + frame.hAy * frame.hAy + frame.hAz * frame.hAz,
    );

    if (!_active) {
      if (hMag > onsetThreshold) {
        _active = true;
        _frameBuf.add(frame);
        _angleBuf.add(angle);
        _quietCount = 0;
      }
    } else {
      _frameBuf.add(frame);
      _angleBuf.add(angle);

      if (hMag < offsetThreshold) {
        _quietCount++;
        if (_quietCount >= quietFrames) _closeWindow();
      } else {
        _quietCount = 0;
      }
      if (_frameBuf.length >= maxWindow) _closeWindow();
    }
  }

  void _closeWindow() {
    if (_frameBuf.length >= minWindow) {
      onMoveComplete(List.of(_frameBuf), List.of(_angleBuf));
    }
    _active = false;
    _frameBuf.clear();
    _angleBuf.clear();
    _quietCount = 0;
    _integrator.reset();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 7: MOVE CLASSIFIER
// ─────────────────────────────────────────────────────────────────────────────

class MoveClassifier {
  static const _rules = <(MoveType, String, bool Function(MoveFeatures))>[
    (MoveType.saute, 'high', _isSaute),
    (MoveType.grandBattement, 'high', _isBattement),
    (MoveType.releve, 'medium', _isReleve),
    (MoveType.pirouette, 'medium', _isPirouette),
    (MoveType.grandPlie, 'low', _isPlie),
  ];

  static bool _isSaute(MoveFeatures f) =>
      f.peakHeelImpact > 2.5 && f.asymmetry < 0.25;

  static bool _isBattement(MoveFeatures f) =>
      f.asymmetry > 0.40 && f.peakForeImpact > 2.0;

  static bool _isReleve(MoveFeatures f) =>
      f.isRising && f.peakForeImpact > 1.5 && f.peakHeelImpact < 1.2;

  static bool _isPirouette(MoveFeatures f) =>
      f.totalRotation > 90 && f.meanRollRate > 30;

  static bool _isPlie(MoveFeatures f) =>
      f.peakAbsAngle < 10 && f.maxRollRate < 60 && !f.isRising;

  /// Returns the first matching move type (priority order above).
  static MoveType classify(MoveFeatures features) {
    for (final (move, _, test) in _rules) {
      if (test(features)) return move;
    }
    return MoveType.unknown;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 8: RISK EVALUATOR
// ─────────────────────────────────────────────────────────────────────────────

class RiskThresholds {
  static const double rollRateWarn = 150.0;
  static const double rollRateDanger = 220.0;
  static const double angleWarn = 15.0;
  static const double angleDanger = 25.0;
  static const double loadRatioWarn = 0.35;
  static const double loadRatioDanger = 0.50;
}

class RiskEvaluator {
  static const _moveBonus = <MoveType, double>{
    MoveType.saute: 10,
    MoveType.grandBattement: 10,
    MoveType.releve: 5,
    MoveType.pirouette: 5,
    MoveType.grandPlie: 0,
    MoveType.unknown: 2,
  };

  static RiskEvent evaluate(MoveFeatures features, MoveType move) {
    double score = 0;
    final flags = <String>[];

    // Roll rate (max 40 pts)
    final rr = features.maxRollRate;
    if (rr >= RiskThresholds.rollRateDanger) {
      score += 40;
      flags.add('Roll rate ${rr.toStringAsFixed(0)}°/s — danger threshold');
    } else if (rr >= RiskThresholds.rollRateWarn) {
      score += 40 *
          (rr - RiskThresholds.rollRateWarn) /
          (RiskThresholds.rollRateDanger - RiskThresholds.rollRateWarn);
      flags.add('Roll rate ${rr.toStringAsFixed(0)}°/s — above warning');
    }

    // Inversion angle (max 30 pts)
    final ang = features.peakAbsAngle;
    if (ang >= RiskThresholds.angleDanger) {
      score += 30;
      flags.add('Inversion ${ang.toStringAsFixed(1)}° — danger threshold');
    } else if (ang >= RiskThresholds.angleWarn) {
      score += 30 *
          (ang - RiskThresholds.angleWarn) /
          (RiskThresholds.angleDanger - RiskThresholds.angleWarn);
    }

    // Load ratio (max 20 pts)
    final lr = features.loadRatio;
    if (lr >= RiskThresholds.loadRatioDanger) {
      score += 20;
      flags.add('Load ratio ${lr.toStringAsFixed(2)} — high lateral force');
    } else if (lr >= RiskThresholds.loadRatioWarn) {
      score += 20 *
          (lr - RiskThresholds.loadRatioWarn) /
          (RiskThresholds.loadRatioDanger - RiskThresholds.loadRatioWarn);
    }

    // Move bonus (max 10 pts)
    score += _moveBonus[move] ?? 0;
    score = score.clamp(0, 100);

    final alert = score >= 65
        ? AlertLevel.danger
        : score >= 35
            ? AlertLevel.warning
            : AlertLevel.safe;

    return RiskEvent(
      move: move,
      riskScore: double.parse(score.toStringAsFixed(1)),
      alert: alert,
      flags: flags,
      features: features,
      timestamp: DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 9: SESSION SCORER
// ─────────────────────────────────────────────────────────────────────────────

class SessionScorer {
  static const _penalty = <AlertLevel, int>{
    AlertLevel.danger: 12,
    AlertLevel.warning: 4,
    AlertLevel.safe: 0,
  };

  final List<RiskEvent> _events = [];
  final DateTime _start = DateTime.now();

  List<RiskEvent> get events => List.unmodifiable(_events);

  void addEvent(RiskEvent ev) => _events.add(ev);

  int get currentScore {
    int s = 100;
    for (final ev in _events) s -= _penalty[ev.alert]!;
    return s.clamp(0, 100);
  }

  SessionSummary finalize(List<String> coaching) {
    final dur = DateTime.now().difference(_start).inMilliseconds / 1000.0;
    final danger = _events.where((e) => e.alert == AlertLevel.danger).length;
    final warning = _events.where((e) => e.alert == AlertLevel.warning).length;

    final moveCounts = <MoveType, int>{};
    final moveRiskAccum = <MoveType, List<double>>{};

    for (final ev in _events) {
      moveCounts[ev.move] = (moveCounts[ev.move] ?? 0) + 1;
      moveRiskAccum.putIfAbsent(ev.move, () => []).add(ev.riskScore);
    }

    final moveAvgRisk = moveRiskAccum
        .map((k, v) => MapEntry(k, v.reduce((a, b) => a + b) / v.length));

    final peakRollRate = _events.isEmpty
        ? 0.0
        : _events.map((e) => e.features.maxRollRate).reduce(math.max);
    final peakAngle = _events.isEmpty
        ? 0.0
        : _events.map((e) => e.features.peakAbsAngle).reduce(math.max);

    MoveType worstMove = MoveType.unknown;
    if (moveAvgRisk.isNotEmpty) {
      worstMove =
          moveAvgRisk.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    return SessionSummary(
      sessionScore: currentScore,
      durationSec: dur,
      totalMoves: _events.length,
      dangerCount: danger,
      warningCount: warning,
      moveCounts: moveCounts,
      moveAvgRisk: moveAvgRisk,
      peakRollRate: peakRollRate,
      peakAngle: peakAngle,
      worstMove: worstMove,
      coaching: coaching,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 10: COACHING FEEDBACK ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class CoachingEngine {
  static List<String> generate(
    SessionSummary session,
    List<SessionSummary> history,
  ) {
    final tips = <String>[];

    if (session.dangerCount == 0 && session.warningCount == 0) {
      tips.add('Clean session — no risk events above warning threshold. '
          'Ankle mechanics look stable across all detected moves.');
      return tips;
    }

    // Roll rate tip
    if (session.peakRollRate > RiskThresholds.rollRateWarn) {
      tips.add(
        'Roll rate hit ${session.peakRollRate.toStringAsFixed(0)}°/s '
        'during ${session.worstMove.label} — above the '
        '${RiskThresholds.rollRateDanger.toStringAsFixed(0)}°/s safe threshold. '
        'Try landing with knees tracking over toes to reduce lateral ankle load.',
      );
    }

    // Angle tip
    if (session.peakAngle > RiskThresholds.angleWarn) {
      tips.add(
        'Ankle reached ${session.peakAngle.toStringAsFixed(1)}° inversion '
        'during ${session.worstMove.label}. '
        'Focus on maintaining a neutral subtalar joint through this phase.',
      );
    }

    // Recurring pattern across last 5 sessions
    if (history.length >= 2) {
      final recent =
          history.length > 5 ? history.sublist(history.length - 5) : history;
      for (final move in session.moveAvgRisk.keys) {
        final count =
            recent.where((h) => (h.moveAvgRisk[move] ?? 0) > 40).length;
        if (count >= 2) {
          tips.add(
            '${move.label} has triggered risk events in $count of your last '
            '${recent.length} sessions. '
            'Consider isolated ankle stability drills before rehearsal.',
          );
        }
      }
    }

    // Improvement shoutout
    if (history.isNotEmpty) {
      final delta = session.sessionScore - history.last.sessionScore;
      if (delta > 3) {
        tips.add(
          'Safety score improved $delta pts this session — '
          '${session.worstMove.label} landings are showing better load distribution.',
        );
      }
    }

    return tips;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK 11: MAIN PIPELINE
// ─────────────────────────────────────────────────────────────────────────────

class PlieSensePipeline {
  final SensorCalibrator _calibrator = SensorCalibrator();
  final LowPassFilter _lpf = LowPassFilter(alpha: 0.3);
  final SessionScorer _scorer = SessionScorer();
  final List<SessionSummary> _history = [];

  late final MoveSegmenter _segmenter;

  /// Fires whenever a move window is evaluated.
  /// Bind this to your Flutter StreamController / ChangeNotifier.
  final StreamController<RiskEvent> riskEvents =
      StreamController<RiskEvent>.broadcast();

  PlieSensePipeline() {
    _segmenter = MoveSegmenter(onMoveComplete: _onMove);
  }

  /// Call for every incoming SensorFrame.
  void ingest(SensorFrame raw) {
    if (!_calibrator.isCalibrated) {
      _calibrator.feed(raw);
      return;
    }
    final calibrated = _calibrator.apply(raw);
    final smoothed = _lpf.process(calibrated);
    _segmenter.push(smoothed);
  }

  void _onMove(List<SensorFrame> window, List<double> angles) {
    final features = FeatureExtractor.extract(window, angles);
    final move = MoveClassifier.classify(features);
    final riskEv = RiskEvaluator.evaluate(features, move);
    _scorer.addEvent(riskEv);
    riskEvents.add(riskEv); // push to UI stream

    _debugPrint(riskEv);
  }

  /// Call when the dancer ends the session.
  SessionSummary endSession() {
    final coaching = CoachingEngine.generate(
      _scorer.finalize([]), // pre-pass for coaching input
      _history,
    );
    final summary = _scorer.finalize(coaching);
    _history.add(summary);
    _debugSummary(summary);
    return summary;
  }

  int get currentScore => _scorer.currentScore;
  bool get isCalibrated => _calibrator.isCalibrated;
  List<RiskEvent> get sessionEvents => _scorer.events;

  void _debugPrint(RiskEvent ev) {
    print('[Event] ${ev.move.label.padRight(20)} '
        'score=${ev.riskScore.toStringAsFixed(1).padLeft(5)} '
        'alert=${ev.alert.name.padRight(8)} '
        '${ev.flags.join(", ")}');
  }

  void _debugSummary(SessionSummary s) {
    print('\n${"=" * 60}');
    print('  SESSION COMPLETE  |  Score: ${s.sessionScore}/100');
    print('${"=" * 60}');
    print('  Duration:    ${s.durationSec.toStringAsFixed(1)}s');
    print('  Total moves: ${s.totalMoves}');
    print('  Danger:      ${s.dangerCount}  Warning: ${s.warningCount}');
    print('  Peak roll:   ${s.peakRollRate.toStringAsFixed(1)}°/s');
    print('  Peak angle:  ${s.peakAngle.toStringAsFixed(1)}°');
    print('  Worst move:  ${s.worstMove.label}');
    print('\n  Coaching:');
    for (final t in s.coaching) print('  • $t');
    print('${"=" * 60}\n');
  }

  void dispose() => riskEvents.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT (pure Dart — swap main() body for Flutter runApp)
// ─────────────────────────────────────────────────────────────────────────────
class PlieSenseProvider extends ChangeNotifier {
  PlieSensePipeline? pipeline;
  HttpReceiver? receiver;

  bool isReady = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final hIp = prefs.getString('pangea_heel_ip');
    final fIp = prefs.getString('pangea_forefoot_ip');

    if (hIp != null && fIp != null) {
      // 1. Initialize the system with BOTH IPs
      pipeline = PlieSensePipeline();
      receiver = HttpReceiver(heelIp: hIp, foreIp: fIp);

      // 2. Subscribe pipeline to incoming dual-frames [cite: 705-706]
      receiver!.frames.listen((frame) {
        pipeline!.ingest(frame);
        notifyListeners(); // Updates the UI with live data
      });

      // 3. Start the HTTP polling loop
      receiver!.start();

      isReady = true;
      notifyListeners();
    }
  }

  // Helper to end session and get the summary [cite: 663-672]
  SessionSummary stopSession() {
    final summary = pipeline!.endSession();
    receiver!.stop();
    notifyListeners();
    return summary;
  }
}
