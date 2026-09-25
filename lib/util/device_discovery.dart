import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

/// Finds sensors on the local Wi-Fi subnet by probing every host address
/// in parallel via /data, instead of relying on a cached IP that goes
/// stale whenever a device gets a new DHCP lease on reconnect (the ESP32
/// comes back online fine, just at a different address than last time).
///
/// The current firmware has no /whoami, so this can only confirm a host
/// is a live sensor — not which physical sensor (heel/forefoot) it is.
/// Callers are responsible for role assignment.
class DeviceDiscovery {
  static Future<List<String>> findLiveSensorIps({
    Duration perHostTimeout = const Duration(milliseconds: 500),
    Duration overallTimeout = const Duration(seconds: 8),
    int maxToFind = 2,
  }) async {
    final found = <String>[];
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp == null) return found;

    final parts = wifiIp.split('.');
    if (parts.length != 4) return found;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final ownLastOctet = int.tryParse(parts[3]);

    final completer = Completer<void>();
    int remaining = 254;

    void countDown() {
      remaining--;
      if (remaining <= 0 && !completer.isCompleted) completer.complete();
    }

    for (int i = 1; i <= 254; i++) {
      if (i == ownLastOctet) {
        countDown();
        continue;
      }
      final candidate = '$prefix.$i';
      http
          .get(Uri.parse('http://$candidate/data'))
          .timeout(perHostTimeout)
          .then((res) {
        if (res.statusCode == 200 && !found.contains(candidate)) {
          found.add(candidate);
          if (found.length >= maxToFind && !completer.isCompleted) {
            completer.complete();
          }
        }
      }).catchError((_) {}).whenComplete(countDown);
    }

    await completer.future.timeout(overallTimeout, onTimeout: () {});
    return found;
  }
}
