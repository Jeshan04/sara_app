/// Raw sensor frame from one poll of both sensors' /data endpoints.
/// Current firmware only reports accel (x/y/z) — no gyro.
class SensorFrame {
  final int ts; // sample timestamp

  // Heel MPU (0x68)
  final double hAx, hAy, hAz; // accel g

  // Forefoot MPU (0x68 on its own board)
  final double fAx, fAy, fAz; // accel g

  const SensorFrame({
    required this.ts,
    required this.hAx,
    required this.hAy,
    required this.hAz,
    required this.fAx,
    required this.fAy,
    required this.fAz,
  });

  SensorFrame copyWith({
    int? ts,
    double? hAx,
    double? hAy,
    double? hAz,
    double? fAx,
    double? fAy,
    double? fAz,
  }) =>
      SensorFrame(
        ts: ts ?? this.ts,
        hAx: hAx ?? this.hAx,
        hAy: hAy ?? this.hAy,
        hAz: hAz ?? this.hAz,
        fAx: fAx ?? this.fAx,
        fAy: fAy ?? this.fAy,
        fAz: fAz ?? this.fAz,
      );
}
