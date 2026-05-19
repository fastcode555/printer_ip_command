# Flutter app for printer_ip_command — design

**Date:** 2026-05-19
**Status:** approved (pending spec review)

## Goal

Build a Flutter app that takes a printer IP and runs the existing 7-channel identify pipeline against it, plus optionally sends a test receipt. Target platforms: **Windows** and **Android** only.

The existing Dart library at the repo root (`lib/printer_ip_command.dart`) already exposes `PrinterIdentifier.identify(host)`, which runs all 6 parallel channel probes (DLE EOT 1, PJL, IPP, SNMP, HTTP, mDNS) plus the serial GS I follow-up, and returns a complete `IdentifyReport` with one `ChannelOutcome` per channel and a merged `DeviceInfo`. The Flutter app is a thin UI on top of that — no wrapper layer, no protocol logic in `app/`.

## Repo layout

The library stays exactly where it is. The Flutter project goes under `app/` and pulls the library in via a path dep.

```
printer_ip_command/                        ← existing repo
├── lib/                                    (unchanged — pure Dart library)
├── bin/                                    (unchanged — CLI tools)
├── test/                                   (unchanged — Dart unit tests)
├── pubspec.yaml                            (unchanged — Dart lib pubspec)
├── docs/superpowers/specs/                 (this document)
└── app/                                  ← NEW Flutter project
    ├── pubspec.yaml                        flutter sdk + printer_ip_command: {path: ../}
    ├── analysis_options.yaml               flutter_lints
    ├── lib/
    │   ├── main.dart                       runApp(PrinterIpApp())
    │   ├── app.dart                        MaterialApp shell, single route → DiagnosePage
    │   ├── services/
    │   │   └── printer_service.dart        identify(ip, deep), printTest(ip, encoding)
    │   ├── pages/
    │   │   └── diagnose_page.dart          IP TextField + deep checkbox + Identify button + result
    │   └── widgets/
    │       ├── device_info_panel.dart      merged DeviceInfo summary card
    │       ├── channel_card.dart           one card per ChannelOutcome (rendered 7×)
    │       └── print_test_dialog.dart      encoding selector + Send button
    ├── test/
    │   └── widget_test.dart                pumps DiagnosePage with fake report
    ├── android/                            flutter create scaffold + cleartext patch
    └── windows/                            flutter create scaffold
```

Nothing in `lib/`, `bin/`, `test/`, root `pubspec.yaml`, `README.md`, or `bin/diagnose.sh` changes. The CLI keeps working as today.

## Component contracts

### `PrinterService` (`app/lib/services/printer_service.dart`)

Thin facade over the library. Two methods. Both are pure async, no UI dependencies, so they're trivially mockable for widget tests.

```dart
class PrinterService {
  Future<IdentifyReport> identify(String host, {bool deep = false});

  /// Returns number of bytes written on success.
  Future<int> printTest(String host, ReceiptEncoding encoding);
}
```

- `identify` delegates to `PrinterIdentifier.identify(host, deep: deep)` with the lib's default 2-second per-channel timeout.
- `printTest` opens a fresh `Socket.connect(host, 9100, timeout: 2s)`, writes `buildReceipt(encoding: encoding)` bytes, flushes, and destroys the socket. Mirrors `bin/force_print.dart`. Any `SocketException` / `TimeoutException` is caught and rethrown as a `PrintTestException` with a human-readable message.

### `DiagnosePage` (`app/lib/pages/diagnose_page.dart`)

Single screen, `StatefulWidget`. Three state variables:
- `String? _ip` — bound to a `TextEditingController`.
- `bool _deep` — bound to the "Include invasive probes" checkbox.
- `Future<IdentifyReport>? _pending` — null when idle; set to the in-flight identify future when Identify is tapped.

UI layout (top to bottom):
1. `TextField` for IP, with IPv4 validator: `^\d{1,3}(\.\d{1,3}){3}$`. Invalid input disables the Identify button.
2. `Checkbox` "Include invasive probes (PJL/ZPL)" — default off.
3. `ElevatedButton` "Identify".
4. Body: `FutureBuilder<IdentifyReport>` on `_pending`:
   - null → idle hint text.
   - waiting → centered `CircularProgressIndicator` + elapsed-time label updating every 100ms.
   - error → `null` (cannot happen; see error handling section).
   - hasData → `DeviceInfoPanel(report.device)` on top, then 7 `ChannelCard`s in fixed order.
5. Footer: `ElevatedButton` "Send test receipt" — visible iff `_pending` has data AND `report.escPosProbe.ok` AND `report.device.protocol == Protocol.escPos`. Opens `PrintTestDialog`.

### `ChannelCard` (`app/lib/widgets/channel_card.dart`)

```dart
class ChannelCard extends StatelessWidget {
  final String channelLabel;       // e.g. "ch1 ESC/POS probe"
  final ChannelStatus status;      // success / failed / skipped
  final Duration elapsed;
  final String summary;            // 1-2 line detail or error string
}
```

Renders: status icon (✓ green / ✗ red / – grey), label, elapsed ms, summary. Fixed height ~80dp. Used 7 times in `DiagnosePage`. The page builds the seven instances directly from `IdentifyReport` fields — no list/iteration, channel order is hard-coded to match `bin/printer_probe.dart` CLI output for operator familiarity.

### `DeviceInfoPanel` (`app/lib/widgets/device_info_panel.dart`)

Stateless. Renders a card showing: vendor, model, firmware, serial, protocol enum name, mDNS hostname, merged document formats (chip list). Null fields render as em-dash.

### `PrintTestDialog` (`app/lib/widgets/print_test_dialog.dart`)

`showDialog` content. Radio group over `ReceiptEncoding` (Big5 / GBK / ASCII), default **Big5** to match the CLI default and the HK production hardware. "Cancel" closes; "Send" awaits `service.printTest(...)` and pops with the result or error. The page shows a snackbar with the outcome.

> **Encoding default rationale and lab note:** the CLI default is Big5 because HK production printers ship with Big5 ROM. The team's lab printer at `192.168.225.78` has a GBK ROM and prints garbage with Big5 — the operator must flip to GBK for that device. We surface this as a runtime selector rather than hard-coding because encoding is hardware-determined (see encoding-is-hardware-determined memory). Default stays Big5 so the dialog matches production behavior out of the box.

## Data flow

```
User types IP
   │
   ▼
Tap Identify
   │
   ▼
DiagnosePage.setState(_pending = service.identify(ip, deep: _deep))
   │
   ▼
PrinterService.identify
   │
   ▼
PrinterIdentifier.identify(host, deep)
   │   ├── Future.wait over 6 channels (probe, pjl?, ipp, snmp, http, mdns)
   │   └── if ESC/POS confirmed, serially run GS I identity
   ▼
IdentifyReport resolves (~2-3s worst case with default 2s timeouts)
   │
   ▼
FutureBuilder rebuilds → DeviceInfoPanel + 7 ChannelCards
   │
   ▼
If escPos: enable "Send test receipt"
   │
   ▼
User taps → PrintTestDialog → service.printTest(ip, encoding)
   │
   ▼
Socket.connect(host, 9100) → buildReceipt(encoding) → flush → close
   │
   ▼
Snackbar: "Sent N bytes" or "Failed: <message>"
```

All work runs on the main isolate. No `compute()`. Default per-channel timeout is 2s, so worst-case identify wall time is ~2-3s — fine for UI responsiveness without isolate offload.

## Error handling

The library's `ChannelOutcome` already encodes status + error string + elapsed per channel. **The Flutter layer adds no error wrapping for identify** — failures inside any channel are caught in `identifier.dart:_run` and surfaced as `ChannelOutcome(status: failed, error: ...)`. The top-level `identify` future cannot fail; it always resolves with a populated `IdentifyReport`.

- **Invalid IP input** → form-field validator blocks the Identify button. No call made.
- **Unroutable host** → all channels resolve as `failed` with `socket: ...` error strings. UI renders all 7 cards red. No exception thrown.
- **Print test socket failure** → caught in `PrinterService.printTest`, rethrown as `PrintTestException`, caught in `DiagnosePage`, surfaced as red snackbar.

## State management

Plain `StatefulWidget` + `setState`. No Provider / Riverpod / BLoC / GetX. The app has one screen and three state variables. Adding a state library here is pure overhead.

## Platform configuration

### Android (`app/android/app/src/main/AndroidManifest.xml`)
- `android:usesCleartextTraffic="true"` on `<application>` — required for HTTP probe to LAN POS printers (Android 9+ blocks cleartext HTTP by default).
- Permissions: `INTERNET` (default in Flutter scaffold), `ACCESS_NETWORK_STATE` (for mDNS to detect Wi-Fi presence).
- `multicast_dns: ^0.3.2` handles `WifiManager.MulticastLock` internally — no extra code or permission needed for that specifically.
- `minSdkVersion`: leave at whatever Flutter's current default is for the scaffold; not pinned by this spec.

### Windows
- No code changes needed beyond `flutter create` scaffold.
- First run will trigger Windows Defender Firewall prompt for outbound TCP/UDP — user accepts once. This is expected and not a bug.

### Dependencies in `app/pubspec.yaml`

```yaml
name: printer_ip_app
description: Flutter UI for printer_ip_command — diagnose printers by IP.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  printer_ip_command:
    path: ../

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

No state-management library, no HTTP client, no extra packages. `enough_convert`, `gbk_codec`, and `multicast_dns` come transitively through the path dep on the root library.

## Testing

### Unchanged
The existing `test/` directory (Dart unit tests for the library) stays as-is. The library has independent tests and they keep running via `dart test` from the repo root.

### New
- `app/test/widget_test.dart` — one widget test that pumps `DiagnosePage` with an injected `PrinterService` mock returning a fixed `IdentifyReport` (built directly with constructors, no network). Verifies: 7 `ChannelCard`s render, status icons match the fixture, "Send test receipt" button is enabled when ESC/POS succeeded and hidden otherwise.

### Manual verification
- `cd app && flutter run -d windows` — point at `192.168.225.78` on the lab subnet, verify all 7 channels resolve per the `test-printer-identity` memory (ch1+ch2 succeed, ch3-7 fail in safe mode).
- `cd app && flutter run -d <android-device>` — same target, same expected channel matrix. From a Mac dev machine the lab IP needs the VPN-bypass route (see `test-printer-vpn-bypass` memory); from a Windows/Android device on the same LAN it's directly reachable.
- Print test from each platform: tap "Send test receipt", select GBK (since lab printer has GBK ROM), verify receipt prints with readable Chinese characters.

## Non-goals

Explicitly out of scope for this spec:
- Saved-device list / IP history (no `shared_preferences` integration).
- Subnet sweep / auto-discovery (no scanning 0-255 on a /24).
- Web platform (raw sockets unavailable; would require a backend relay).
- iOS / macOS / Linux platform scaffolds (can be `flutter create`'d later if needed).
- Per-channel streaming UI (results land all at once when `Future.wait` completes — fine for a 2-3s diagnostic wait).
- State management library — `setState` covers everything in a single-screen app.
- Localization. English UI; channel labels match CLI output (`ch1 ESC/POS probe`, etc.) for operator familiarity.
- Theming / branding polish. Default Material 3 light theme is the baseline.
- Logging / analytics. No telemetry shipped.
