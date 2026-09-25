import 'dart:async';

import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pangea/util/app_colors.dart';
import 'package:pangea/util/mytextfield.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../home_page.dart';
import '../util/device_discovery.dart';

class TestProvisioningScreen extends StatefulWidget {
  const TestProvisioningScreen({super.key, required this.title});
  final String title;

  @override
  State<TestProvisioningScreen> createState() => _TestProvisioningScreenState();
}

class _TestProvisioningScreenState extends State<TestProvisioningScreen> {
  final passwordController = TextEditingController();
  String? _selectedSSID;
  List<WiFiAccessPoint> _accessPoints = [];
  bool _isScanning = false;
  bool _isProvisioning = false;
  bool _isCheckingConnection = true;
  bool _isSearchingNetwork = false;
  bool _obscurePassword = true;

  // Dual Sensor Discovery State
  String? _heelIp;
  String? _forefootIp;
  final Set<String> _processedIps = {};

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
  }

  // --- Auto-Reconnect Logic for DUAL Sensors ---
  Future<void> _checkExistingConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final hIp = prefs.getString('pangea_heel_ip');
    final fIp = prefs.getString('pangea_forefoot_ip');

    if (hIp != null && fIp != null) {
      // A couple of quick retries: right after the ESP32 reconnects to
      // Wi-Fi its HTTP server can take a moment to answer. The current
      // firmware has no /whoami, so /data is both the liveness check and
      // the only route that exists.
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final responses = await Future.wait([
            http
                .get(Uri.parse('http://$hIp/data'))
                .timeout(const Duration(seconds: 2)),
            http
                .get(Uri.parse('http://$fIp/data'))
                .timeout(const Duration(seconds: 2)),
          ]);
          if (responses.every((r) => r.statusCode == 200) && mounted) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const TestHomePage()));
            return;
          }
        } catch (_) {}
        if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
      }

      // Cached IPs are stale — most likely both sensors auto-reconnected
      // on their own (that's the point of the firmware's auto-reconnect)
      // but got handed different DHCP leases than last time. Scan the
      // subnet for them instead of forcing the user through SmartConfig
      // again, which won't work anyway since the sensors only listen
      // for it once at boot.
      if (mounted) setState(() => _isSearchingNetwork = true);
      final foundIps = await DeviceDiscovery.findLiveSensorIps();
      if (mounted) setState(() => _isSearchingNetwork = false);

      // Firmware doesn't expose an identity, so we can't tell which
      // rediscovered IP is which sensor — keep whichever role each IP
      // already held if it's still alive, and only reassign roles that
      // actually went missing.
      final stillHeel = foundIps.contains(hIp) ? hIp : null;
      final stillFore = foundIps.contains(fIp) ? fIp : null;
      final leftover =
          foundIps.where((ip) => ip != stillHeel && ip != stillFore).toList();
      final newHeelIp = stillHeel ?? (leftover.isNotEmpty ? leftover.removeAt(0) : null);
      final newForeIp = stillFore ?? (leftover.isNotEmpty ? leftover.removeAt(0) : null);
      if (newHeelIp != null && newForeIp != null) {
        await prefs.setString('pangea_heel_ip', newHeelIp);
        await prefs.setString('pangea_forefoot_ip', newForeIp);
        if (mounted) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => const TestHomePage()));
          return;
        }
      }
    }

    // No saved IPs, or the sensors genuinely can't be found on this
    // network — fall back to manual SmartConfig provisioning.
    if (mounted) {
      setState(() => _isCheckingConnection = false);
      _startScan();
    }
  }

  // --- Password Manager: Recall ---
  Future<void> _loadSavedPassword(String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    String? savedPwd = prefs.getString('wifi_pwd_$ssid');
    if (mounted) {
      setState(() {
        passwordController.text = savedPwd ?? "";
      });
    }
  }

  // --- Password Manager: Save ---
  Future<void> _saveWifiPassword(String ssid, String pwd) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wifi_pwd_$ssid', pwd);
  }

  Future<void> _startScan() async {
    if (await Permission.locationWhenInUse.request().isGranted) {
      setState(() => _isScanning = true);
      if (await WiFiScan.instance.canStartScan() == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 1));
      }
      final results = await WiFiScan.instance.getScannedResults();
      setState(() {
        _accessPoints = results.where((ap) => ap.frequency < 3000).toList();
        _isScanning = false;
      });
    }
  }

  Future<void> _startProvisioning() async {
    if (_selectedSSID == null) return;

    // Save password for this SSID immediately
    await _saveWifiPassword(_selectedSSID!, passwordController.text);

    setState(() {
      _isProvisioning = true;
      _heelIp = null;
      _forefootIp = null;
      _processedIps.clear();
    });

    final provisioner = Provisioner.espTouch();

    provisioner.listen((response) {
      final ip = response.ipAddressText;
      if (ip != null && !_processedIps.contains(ip)) {
        _processedIps.add(ip);
        _confirmLiveThenAssign(ip);
      }
    });

    provisioner.start(ProvisioningRequest.fromStrings(
      ssid: _selectedSSID!,
      bssid: '00:00:00:00:00:00',
      password: passwordController.text,
    ));

    // SmartConfig only works while the sensors are actively listening for
    // it at boot — if either one never responds (or already auto-reconnected
    // with stored credentials) this would otherwise wait forever with no
    // way out. Bound it, and let the user cancel manually too.
    final timeoutTimer = Timer(const Duration(seconds: 25), () {
      if (mounted) Navigator.of(context).pop();
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DualSyncDialog(
        isHeelFound: () => _heelIp != null,
        isForeFound: () => _forefootIp != null,
        onCancel: () => Navigator.pop(context),
      ),
    );

    timeoutTimer.cancel();
    provisioner.stop();
    setState(() => _isProvisioning = false);

    if (_heelIp != null && _forefootIp != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pangea_heel_ip', _heelIp!);
      await prefs.setString('pangea_forefoot_ip', _forefootIp!);
      if (mounted)
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const TestHomePage()));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't reach both sensors via SmartConfig. Make sure both "
            "are powered on and showing a blue LED, then try again.",
          ),
        ),
      );
    }
  }

  // Current firmware has no /whoami, so there's no way to ask a sensor
  // which role it is. Confirm it's actually alive via /data, then assign
  // it to whichever role slot is still open — first sensor to respond
  // becomes the heel, second becomes the forefoot.
  Future<void> _confirmLiveThenAssign(String ip, {int retries = 5}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final res = await http
            .get(Uri.parse('http://$ip/data'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          if (_heelIp == null) {
            _heelIp = ip;
          } else if (_forefootIp == null && ip != _heelIp) {
            _forefootIp = ip;
          }
          if (mounted) setState(() {});
          return;
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    if (_isCheckingConnection) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: accent),
              const SizedBox(height: 16),
              Text(
                _isSearchingNetwork
                    ? "Sensors moved — searching the network..."
                    : "Checking for saved sensors...",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            children: [
              Icon(Icons.double_arrow, size: 60, color: accent),
              const SizedBox(height: 20),
              const Text("Dual-Sensor Provisioning",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              _buildDropdown(isDark),
              const SizedBox(height: 16),
              MyTextField(
                hint: 'Password',
                obscureText: _obscurePassword,
                controller: passwordController,
                icon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: (_isProvisioning || _selectedSSID == null)
                      ? null
                      : _startProvisioning,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15))),
                  child: const Text("PAIR BOTH SENSORS",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
              TextButton(
                  onPressed: _startScan, child: const Text("Refresh Networks")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(15),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: _selectedSSID,
          hint: Text(_isScanning ? "Scanning..." : "Select Wi-Fi"),
          items: _accessPoints
              .map((ap) =>
                  DropdownMenuItem(value: ap.ssid, child: Text(ap.ssid)))
              .toList(),
          onChanged: (v) {
            setState(() => _selectedSSID = v);
            if (v != null) _loadSavedPassword(v);
          },
          decoration: const InputDecoration(
              border: InputBorder.none, icon: Icon(Icons.wifi)),
        ),
      ),
    );
  }
}

/// Dialog shown while SmartConfig is broadcasting. Polls the parent's
/// `_heelIp`/`_forefootIp` fields via the passed-in getters on its own
/// timer, which is properly disposed when the dialog closes — unlike a
/// StatefulBuilder whose builder callback would spawn a fresh
/// Timer.periodic on every single rebuild.
class _DualSyncDialog extends StatefulWidget {
  final bool Function() isHeelFound;
  final bool Function() isForeFound;
  final VoidCallback onCancel;

  const _DualSyncDialog({
    required this.isHeelFound,
    required this.isForeFound,
    required this.onCancel,
  });

  @override
  State<_DualSyncDialog> createState() => _DualSyncDialogState();
}

class _DualSyncDialogState extends State<_DualSyncDialog> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heelFound = widget.isHeelFound();
    final foreFound = widget.isForeFound();
    final allFound = heelFound && foreFound;

    return AlertDialog(
      title: const Text("Syncing Dual Sensors"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
          _statusIcon("Heel Sensor", heelFound),
          _statusIcon("Forefoot Sensor", foreFound),
        ],
      ),
      actions: [
        if (allFound)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CONTINUE"),
          )
        else
          TextButton(
            onPressed: widget.onCancel,
            child: const Text("CANCEL"),
          ),
      ],
    );
  }
}

Widget _statusIcon(String label, bool detected) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(detected ? Icons.check_circle : Icons.hourglass_empty,
            color: detected ? Colors.green : Colors.orange),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontWeight: detected ? FontWeight.bold : FontWeight.normal)),
      ],
    ),
  );
}
