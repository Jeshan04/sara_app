# Context — Sara's App (PliéSense)

Ballet ankle-injury prevention app. Flutter app (package name `pangea`, app title "Sara's App")
paired with two ESP32-C3 SuperMini hardware sensor units strapped to the dancer's ankle
(heel + forefoot), each with an MPU6050 IMU, RGB status LED, and a WiFi HTTP server.

## Hardware / firmware (as provided)

- Board: ESP32-C3 SuperMini. I2C on SDA=8, SCL=9. RGB status LED on pins 2/3/4 (common anode).
- One MPU6050 per board at fixed I2C address `0x68`.
- WiFi provisioning via **ESP SmartConfig** (`WiFi.beginSmartConfig()`), TX power capped at 8.5dBm.
- LED convention: blue = waiting for SmartConfig, green = connected, red = MPU init failed (halts in `while(1)`).
- Single HTTP route: `GET /data` → reads accel registers only (`0x3B`, 6 bytes = X/Y/Z accel),
  scales by `/16384.0` (±2g range), returns:
  ```json
  {"x": 0.001, "y": 0.002, "z": 0.998}
  ```
- No gyro read anywhere (gyro registers `0x43+` are never touched).
- No `/whoami` route or any other endpoint besides `/data`.
- No persisted device identity (heel vs. forefoot) — both boards would run identical firmware/behavior.

## Flutter app — actual live screen flow

`main.dart``RootWrapper` decides screen from Firebase auth + `SharedPreferences` flags:

1. Not logged in → `LoginScreen` (`loginpage.dart`)
2. Logged in, `session_provisioned == false` → `TestProvisioningScreen` (`data_collection/test_provisioning.dart`)
   — WiFi scan + SmartConfig broadcast to pair **two** sensors at once. For each IP that responds
   to SmartConfig, it calls `GET /whoami` and expects the literal body `"HEEL"` or `"FOREFOOT"` to
   sort it into `pangea_heel_ip` / `pangea_forefoot_ip` (SharedPreferences). Waits until both are found.
3. Otherwise → `TestHomePage` (`home_page.dart`, "Hi, Sara!" welcome screen) → button → `BaselinePage`
4. `BaselinePage` (`baseline_page.dart`) — polls `GET /whoami` on both saved IPs every 3s to show
   connection dots; "Record Baseline" calls `GET /data` on both and saves `ax,ay,az,gx,gy,gz` for
   both heel and forefoot into SharedPreferences (`base_hAx` … `base_fGz`) as static bias offsets.
5. `TestPage` (`test_page.dart`) — "Dual Sensor Live" dashboard. Polls `GET /data` on both IPs every
   500ms, parses JSON keys `ax,ay,az,gx,gy,gz` into a local `SensorFrame` (`lib/sensor_frame.dart`),
   and displays raw accel X/Y/Z per sensor as live numbers. **This is the only screen currently
   reachable that talks to the sensors during a "session" — it does no risk scoring, just a live readout.**

## The real signal-processing pipeline exists but is NOT wired up

`lib/pipeline/plie_sense_core.dart` is a full, self-contained pipeline (calibration → low-pass
filter → ankle-angle integration → move segmentation → move classification [sauté / grand
battement / relevé / pirouette / grand plié] → risk scoring → session scoring → coaching tips).
It expects `SensorFrame` with `ax,ay,az,gx,gy,gz` for **both** heel and forefoot at ~100Hz via its
own `HttpReceiver` (polls `/data` every 10ms) and exposes a `PlieSenseProvider extends ChangeNotifier`
at the bottom of that same file.

`lib/pipeline/plie_sense_provider.dart` is a **second, different, broken** `PlieSenseProvider` class
(duplicate name in the same package) that references a `UdpReceiver` class that doesn't exist
anywhere in the codebase (only `HttpReceiver` exists, in `plie_sense_core.dart`). Nothing imports
`plie_sense_provider.dart` — confirmed via grep — so it doesn't currently break the build, but it's
dead/broken scaffolding, not real code.

Nothing in the live screen flow (`main.dart` → … → `test_page.dart`) imports `plie_sense_core.dart`
or instantiates `PlieSensePipeline`. The risk/move-classification/coaching engine is fully written
but disconnected from the UI.

There's also a second, separate `SensorFrame` class definition: the standalone
`lib/sensor_frame.dart` (used by `test_page.dart`) vs. the one embedded in `plie_sense_core.dart`
Block 1. They're structurally identical but are two separate types — fine today since no file
imports both, but a trap waiting to happen if the pipeline is ever wired into `test_page.dart` directly.

## Firmware ↔ app contract mismatches (blocking issues)

1. **JSON key mismatch**: firmware sends `{"x","y","z"}`; every app call site
   (`baseline_page.dart`, `test_page.dart`, `plie_sense_core.dart`) expects
   `{"ax","ay","az","gx","gy","gz"}`. Every `/data` parse in the app will throw/null today.
2. **No gyro data at all**: firmware only reads the 6 accel bytes from `0x3B`. The entire pipeline's
   core risk signal — roll rate (`fGz`) and the ankle-angle complementary filter
   (`AnkleAngleIntegrator`, gyro + accel fusion) — depends on gyro (`gx,gy,gz`), which the firmware
   never reads or transmits. This has to be added (read 14 bytes from `0x3B` through `0x48`, or two
   reads) before the pipeline can produce anything meaningful.
3. **No `/whoami` route**: both `test_provisioning.dart`'s pairing flow and `baseline_page.dart`'s
   connection-status polling depend on `GET /whoami` returning `200` with body `"HEEL"` or
   `"FOREFOOT"`. Firmware has no such route, so provisioning can never distinguish/confirm the two
   boards and baseline connection dots will always read red. This is presumably meant to be a
   per-board compile-time constant (`#define SENSOR_ROLE "HEEL"` flashed differently per board) or
   set via SmartConfig extra data — needs a decision.

## Status

Fixed firmware saved at `firmware/ankle_sensor/ankle_sensor.ino`:
- `/data` now returns `{"ax","ay","az","gx","gy","gz"}` (gyro added via a single 14-byte burst
  read of registers `0x3B`–`0x48`, scaled `/131.0` for the default ±250°/s range).
- Added `/whoami` returning `SENSOR_ROLE` (`"HEEL"` or `"FOREFOOT"`), a `#define` at the top of
  the file — flash the sketch once as-is for the heel board, flip the define to `"FOREFOOT"` and
  reflash for the second board.

Original 3 blocking mismatches (JSON keys, missing gyro, missing `/whoami`) are resolved on the
firmware side. Not yet done: flashing/testing on real hardware, and the app-side items below.

**Provisioning reliability fix** (`lib/data_collection/test_provisioning.dart`): the dual-sensor
pairing dialog had no timeout and no cancel button — if either sensor didn't identify via
`/whoami`, it hung forever. Also had a timer leak (a new `Timer.periodic` spawned on every
`StatefulBuilder` rebuild). Fixed by porting the pattern from the sibling `pangea` app
(`/Users/eshan/Athena/pangea`, its own single-sensor GSR wearable project): a bounded 25s timeout,
a visible Cancel button, a proper disposable `_DualSyncDialog` widget, and a new
`lib/util/device_discovery.dart` that retries cached IPs 3× then falls back to a parallel subnet
scan for both `/whoami` roles before forcing the user through full SmartConfig re-pairing.

## Open items to decide before writing code

- Firmware: add gyro read (14-byte burst read `0x3B`–`0x48`) and gyro scaling (`/131.0` for default
  ±250°/s), rename JSON keys to `ax/ay/az/gx/gy/gz`, add `/whoami` route with a per-board identity.
- App: decide whether to wire `plie_sense_core.dart`'s `PlieSensePipeline` into `TestPage` (replacing
  its ad-hoc polling) or keep `TestPage` as a raw-readout debug view and add a separate "session" screen.
- Delete or fix `lib/pipeline/plie_sense_provider.dart` (dead, broken, name-collides with the
  provider already defined at the bottom of `plie_sense_core.dart`).
- Reconcile the two `SensorFrame` definitions (`lib/sensor_frame.dart` vs. the one in
  `plie_sense_core.dart`) into one shared model before both are used in the same file.
