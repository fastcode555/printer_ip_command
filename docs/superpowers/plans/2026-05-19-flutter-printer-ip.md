# Flutter printer_ip app — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter app under `app/` (Windows + Android) that takes a printer IP, runs the existing 7-channel `PrinterIdentifier.identify` pipeline from the root library, and offers a "send test receipt" action when ESC/POS is confirmed.

**Architecture:** The existing Dart library at the repo root stays unchanged. A new Flutter project under `app/` depends on it via `path: ../`. UI is a single screen with `StatefulWidget` + `setState` — no state-management library. All probes already run in parallel inside the library; the Flutter layer is a thin renderer.

**Tech Stack:** Flutter 3.27+, Dart 3.6+, Material 3, plain `setState`. Path dep on the existing `printer_ip_command` package — brings `enough_convert`, `gbk_codec`, `multicast_dns` transitively.

**Spec reference:** `docs/superpowers/specs/2026-05-19-flutter-printer-ip-design.md`

---

## File Structure

**Created** (all under `app/`):
- `app/pubspec.yaml` — Flutter pubspec with path dep
- `app/analysis_options.yaml` — `package:flutter_lints/flutter.yaml`
- `app/lib/main.dart` — `runApp(const PrinterIpApp())`
- `app/lib/app.dart` — `MaterialApp` shell, single route → `DiagnosePage`
- `app/lib/services/printer_service.dart` — `PrinterService` class, `PrintTestException`
- `app/lib/pages/diagnose_page.dart` — IP input + Identify button + result view
- `app/lib/widgets/channel_card.dart` — leaf widget for one `ChannelOutcome`
- `app/lib/widgets/device_info_panel.dart` — merged `DeviceInfo` card
- `app/lib/widgets/print_test_dialog.dart` — encoding selector dialog
- `app/test/smoke_test.dart` — verifies path dep import works
- `app/test/widgets/channel_card_test.dart`
- `app/test/widgets/device_info_panel_test.dart`
- `app/test/widgets/print_test_dialog_test.dart`
- `app/test/services/printer_service_test.dart`
- `app/test/pages/diagnose_page_test.dart`
- `app/android/...` — `flutter create` scaffold + manifest patch
- `app/windows/...` — `flutter create` scaffold

**Untouched:** `lib/`, `bin/`, `test/`, root `pubspec.yaml`, `README.md`.

---

## Task 1: Scaffold Flutter project

**Files:**
- Create: `app/` (via `flutter create`)

- [ ] **Step 1: Verify Flutter version**

Run: `flutter --version`
Expected: `Flutter 3.27.0` or higher, channel stable. If lower, run `flutter upgrade` first.

- [ ] **Step 2: Scaffold the Flutter project**

Run from repo root (`/Users/barry/Code/github/printer_ip_command`):

```bash
flutter create \
  --org com.printerip \
  --project-name printer_ip_app \
  --platforms=windows,android \
  --no-pub \
  app
```

Expected output: `Wrote N files.` and `All done!`. The `--no-pub` defers `pub get` until we replace the pubspec in Task 2.

- [ ] **Step 3: Sanity check the scaffold**

Run: `ls app/`
Expected: `lib/  android/  windows/  pubspec.yaml  test/  analysis_options.yaml  ...`

- [ ] **Step 4: Commit**

```bash
git add app/
git commit -m "scaffold Flutter app under app/ (windows + android)"
```

---

## Task 2: Wire path dep and smoke test the import

**Files:**
- Overwrite: `app/pubspec.yaml`
- Create: `app/test/smoke_test.dart`
- Delete: `app/test/widget_test.dart` (default scaffold test, replaced later)

- [ ] **Step 1: Overwrite `app/pubspec.yaml`**

Replace the entire file with:

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

flutter:
  uses-material-design: true
```

- [ ] **Step 2: Delete the default scaffold widget test**

Run: `rm app/test/widget_test.dart`

That test imports the default counter app we're about to delete. Removing it now keeps `flutter test` green between commits.

- [ ] **Step 3: Write the smoke test**

Create `app/test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  test('lib types are importable via path dep', () {
    expect(Protocol.escPos, isA<Protocol>());
    expect(ChannelStatus.success, isA<ChannelStatus>());
    expect(ReceiptEncoding.big5, isA<ReceiptEncoding>());
  });
}
```

- [ ] **Step 4: Run `flutter pub get`**

Run: `cd app && flutter pub get`
Expected: `Got dependencies!` with no errors. If you see a version conflict on `enough_convert` or `gbk_codec`, the path dep is wired correctly — those are transitive from the root lib.

- [ ] **Step 5: Run the smoke test**

Run: `cd app && flutter test test/smoke_test.dart`
Expected: `All tests passed!` and the test resolves the three lib symbols.

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/test/smoke_test.dart
git rm app/test/widget_test.dart
git commit -m "wire path dep on printer_ip_command + smoke test"
```

---

## Task 3: `ChannelCard` widget (TDD)

**Files:**
- Create: `app/lib/widgets/channel_card.dart`
- Test: `app/test/widgets/channel_card_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/channel_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/widgets/channel_card.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('success card shows green check + label + elapsed + summary',
      (tester) async {
    await tester.pumpWidget(_wrap(const ChannelCard(
      label: 'ch1 ESC/POS probe',
      status: ChannelStatus.success,
      elapsed: Duration(milliseconds: 123),
      summary: 'protocol: escPos',
    )));

    expect(find.text('ch1 ESC/POS probe'), findsOneWidget);
    expect(find.text('123 ms'), findsOneWidget);
    expect(find.text('protocol: escPos'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('failed card shows red cross + error summary', (tester) async {
    await tester.pumpWidget(_wrap(const ChannelCard(
      label: 'ch5 SNMP',
      status: ChannelStatus.failed,
      elapsed: Duration(seconds: 2),
      summary: 'timeout: SNMP',
    )));

    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.text('timeout: SNMP'), findsOneWidget);
  });

  testWidgets('skipped card shows grey dash', (tester) async {
    await tester.pumpWidget(_wrap(const ChannelCard(
      label: 'ch3 PJL',
      status: ChannelStatus.skipped,
      elapsed: Duration.zero,
      summary: 'only runs with deep',
    )));

    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/channel_card_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:printer_ip_app/widgets/channel_card.dart'`.

- [ ] **Step 3: Implement the widget**

Create `app/lib/widgets/channel_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class ChannelCard extends StatelessWidget {
  final String label;
  final ChannelStatus status;
  final Duration elapsed;
  final String summary;

  const ChannelCard({
    super.key,
    required this.label,
    required this.status,
    required this.elapsed,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${elapsed.inMilliseconds} ms',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(summary,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    switch (status) {
      case ChannelStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ChannelStatus.failed:
        return const Icon(Icons.cancel, color: Colors.red);
      case ChannelStatus.skipped:
        return const Icon(Icons.remove_circle_outline, color: Colors.grey);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/channel_card_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/channel_card.dart app/test/widgets/channel_card_test.dart
git commit -m "ChannelCard widget + tests"
```

---

## Task 4: `DeviceInfoPanel` widget (TDD)

**Files:**
- Create: `app/lib/widgets/device_info_panel.dart`
- Test: `app/test/widgets/device_info_panel_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/device_info_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/widgets/device_info_panel.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders vendor / model / firmware / serial', (tester) async {
    const device = DeviceInfo(
      host: '192.168.225.78',
      protocol: Protocol.escPos,
      vendor: 'EPSON',
      model: 'TM-T88III',
      firmware: '8.00 ESC/POS',
      serial: 'E2QG064874',
    );

    await tester.pumpWidget(_wrap(const DeviceInfoPanel(device: device)));

    expect(find.text('EPSON'), findsOneWidget);
    expect(find.text('TM-T88III'), findsOneWidget);
    expect(find.text('8.00 ESC/POS'), findsOneWidget);
    expect(find.text('E2QG064874'), findsOneWidget);
    expect(find.text('192.168.225.78'), findsOneWidget);
    expect(find.text('escPos'), findsOneWidget);
  });

  testWidgets('renders em-dash for null fields', (tester) async {
    const device = DeviceInfo(
      host: '10.0.0.1',
      protocol: Protocol.unknown,
    );

    await tester.pumpWidget(_wrap(const DeviceInfoPanel(device: device)));

    expect(find.text('—'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the widget**

Create `app/lib/widgets/device_info_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class DeviceInfoPanel extends StatelessWidget {
  final DeviceInfo device;

  const DeviceInfoPanel({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            _row('host', device.host),
            _row('protocol', _enumName(device.protocol)),
            _row('vendor', device.vendor),
            _row('model', device.model),
            _row('firmware', device.firmware),
            _row('serial', device.serial),
            _row('mDNS hostname', device.mdnsHostname),
            if (device.documentFormats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: device.documentFormats
                      .map((f) => Chip(label: Text(f, style: const TextStyle(fontSize: 11))))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value ?? '—')),
        ],
      ),
    );
  }

  String _enumName(Protocol p) => p.toString().split('.').last;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/device_info_panel.dart app/test/widgets/device_info_panel_test.dart
git commit -m "DeviceInfoPanel widget + tests"
```

---

## Task 5: `PrinterService` + `PrintTestException` (TDD)

**Files:**
- Create: `app/lib/services/printer_service.dart`
- Test: `app/test/services/printer_service_test.dart`

The test runs a local TCP server on an ephemeral port, calls `printTest` against it, and verifies the bytes received start with ESC `@` (the `_init` sequence from `buildReceipt`). The error-wrapping test connects to a closed port and asserts `PrintTestException` is thrown.

- [ ] **Step 1: Write the failing test**

Create `app/test/services/printer_service_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/services/printer_service.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  group('PrinterService.printTest', () {
    test('sends ESC @ init bytes to listening socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final receivedCompleter = Completer<List<int>>();
      server.listen((socket) {
        final buf = <int>[];
        socket.listen(
          buf.addAll,
          onDone: () {
            if (!receivedCompleter.isCompleted) receivedCompleter.complete(buf);
          },
        );
      });

      final service = PrinterService();
      final n = await service.printTest(
        server.address.address,
        ReceiptEncoding.ascii,
        port: server.port,
      );

      expect(n, greaterThan(0));
      final received = await receivedCompleter.future
          .timeout(const Duration(seconds: 3));
      // First two bytes of buildReceipt output are ESC @ (init).
      expect(received[0], 0x1B);
      expect(received[1], 0x40);

      await server.close();
    });

    test('wraps connection refusal as PrintTestException', () async {
      // Bind then immediately close to obtain a port that's guaranteed closed.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();

      final service = PrinterService();
      expect(
        () => service.printTest(
          InternetAddress.loopbackIPv4.address,
          ReceiptEncoding.ascii,
          port: closedPort,
          connectTimeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<PrintTestException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/printer_service_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:printer_ip_app/services/printer_service.dart'`.

- [ ] **Step 3: Implement the service**

Create `app/lib/services/printer_service.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:printer_ip_command/printer_ip_command.dart';

class PrintTestException implements Exception {
  final String message;
  PrintTestException(this.message);
  @override
  String toString() => 'PrintTestException: $message';
}

class PrinterService {
  Future<IdentifyReport> identify(String host, {bool deep = false}) {
    return PrinterIdentifier.identify(host, deep: deep);
  }

  /// Returns the number of bytes written.
  Future<int> printTest(
    String host,
    ReceiptEncoding encoding, {
    int port = 9100,
    Duration connectTimeout = const Duration(seconds: 3),
  }) async {
    final bytes = buildReceipt(
      title: '识别探测',
      lines: [
        '--------------------------------',
        'IP    : $host',
        'Port  : $port',
        'Time  : ${DateTime.now().toIso8601String()}',
        '--------------------------------',
        '如果你看到这张纸,这台机',
        '是 ESC/POS 兼容的热敏打印机。',
        '编码: ${encoding.name}',
      ],
      encoding: encoding,
    );

    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException catch (e) {
      throw PrintTestException('connect failed: ${e.message}');
    } on TimeoutException {
      throw PrintTestException('connect timeout after ${connectTimeout.inSeconds}s');
    }

    try {
      socket.add(bytes);
      await socket.flush();
      // Some thermals need a brief pause before the FIN; without it the cut
      // command can arrive at the printer before the spool buffer drains.
      // Mirrors bin/force_print.dart.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } finally {
      await socket.close();
    }
    return bytes.length;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/printer_service_test.dart`
Expected: `All tests passed!` (two tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/printer_service.dart app/test/services/printer_service_test.dart
git commit -m "PrinterService.identify + printTest with TCP socket test"
```

---

## Task 6: `PrintTestDialog` widget (TDD)

**Files:**
- Create: `app/lib/widgets/print_test_dialog.dart`
- Test: `app/test/widgets/print_test_dialog_test.dart`

The dialog returns the selected `ReceiptEncoding` via `Navigator.pop`. The page (Task 7) then awaits the future and calls the service.

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/print_test_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/widgets/print_test_dialog.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  testWidgets('default selection is Big5, Send returns selected encoding',
      (tester) async {
    ReceiptEncoding? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showPrintTestDialog(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Default radio is Big5 — tapping Send returns it.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, ReceiptEncoding.big5);
  });

  testWidgets('selecting GBK then Send returns GBK', (tester) async {
    ReceiptEncoding? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showPrintTestDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GBK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, ReceiptEncoding.gbk);
  });

  testWidgets('Cancel returns null', (tester) async {
    ReceiptEncoding? result = ReceiptEncoding.ascii;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showPrintTestDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/print_test_dialog_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the dialog**

Create `app/lib/widgets/print_test_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

/// Shows the encoding-selector dialog and returns the chosen encoding
/// (or null if cancelled).
Future<ReceiptEncoding?> showPrintTestDialog(BuildContext context) {
  return showDialog<ReceiptEncoding>(
    context: context,
    builder: (_) => const _PrintTestDialog(),
  );
}

class _PrintTestDialog extends StatefulWidget {
  const _PrintTestDialog();

  @override
  State<_PrintTestDialog> createState() => _PrintTestDialogState();
}

class _PrintTestDialogState extends State<_PrintTestDialog> {
  ReceiptEncoding _selected = ReceiptEncoding.big5;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send test receipt'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Encoding (must match printer ROM):'),
          const SizedBox(height: 8),
          RadioListTile<ReceiptEncoding>(
            title: const Text('Big5'),
            subtitle: const Text('Traditional Chinese — HK/TW market'),
            value: ReceiptEncoding.big5,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
          RadioListTile<ReceiptEncoding>(
            title: const Text('GBK'),
            subtitle: const Text('Simplified Chinese — mainland market'),
            value: ReceiptEncoding.gbk,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
          RadioListTile<ReceiptEncoding>(
            title: const Text('ASCII'),
            subtitle: const Text('No Chinese — works on any printer'),
            value: ReceiptEncoding.ascii,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/print_test_dialog_test.dart`
Expected: `All tests passed!` (three tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/print_test_dialog.dart app/test/widgets/print_test_dialog_test.dart
git commit -m "PrintTestDialog with Big5 default + radio selector"
```

---

## Task 7: `DiagnosePage` (TDD)

**Files:**
- Create: `app/lib/pages/diagnose_page.dart`
- Test: `app/test/pages/diagnose_page_test.dart`

Uses an injected `PrinterService`. Tests subclass `PrinterService` with a fake that returns canned `IdentifyReport`s — no network.

- [ ] **Step 1: Write the failing test**

Create `app/test/pages/diagnose_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/pages/diagnose_page.dart';
import 'package:printer_ip_app/services/printer_service.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class _FakeService extends PrinterService {
  final IdentifyReport canned;
  int calls = 0;
  _FakeService(this.canned);
  @override
  Future<IdentifyReport> identify(String host, {bool deep = false}) async {
    calls++;
    return canned;
  }
}

IdentifyReport _report({
  required Protocol protocol,
  ChannelStatus probeStatus = ChannelStatus.success,
}) {
  return IdentifyReport(
    host: '192.168.225.78',
    escPosProbe: ChannelOutcome<ProbeResult>(
      status: probeStatus,
      elapsed: const Duration(milliseconds: 50),
      error: probeStatus == ChannelStatus.failed ? 'timeout' : '',
    ),
    gsIdentity: const ChannelOutcome<EscPosIdentity>(
      status: ChannelStatus.success,
      elapsed: Duration(milliseconds: 80),
    ),
    pjl: const ChannelOutcome<PjlResult>(
      status: ChannelStatus.skipped,
      elapsed: Duration.zero,
      error: 'only runs with --deep',
    ),
    ipp: const ChannelOutcome<IppResult>(
      status: ChannelStatus.failed,
      elapsed: Duration(seconds: 2),
      error: 'no IPP response',
    ),
    snmp: const ChannelOutcome<SnmpResult>(
      status: ChannelStatus.failed,
      elapsed: Duration(seconds: 2),
      error: 'no SNMP response',
    ),
    http: const ChannelOutcome<HttpFingerprint>(
      status: ChannelStatus.failed,
      elapsed: Duration(seconds: 2),
      error: 'TCP RST',
    ),
    mdns: const ChannelOutcome<MdnsResult>(
      status: ChannelStatus.failed,
      elapsed: Duration(seconds: 2),
      error: 'no advertise',
    ),
    device: DeviceInfo(host: '192.168.225.78', protocol: protocol),
  );
}

void main() {
  testWidgets('Identify button disabled until valid IP entered', (tester) async {
    final service = _FakeService(_report(protocol: Protocol.escPos));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: service)));

    final identifyBtn = find.widgetWithText(ElevatedButton, 'Identify');
    expect(
      tester.widget<ElevatedButton>(identifyBtn).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '192.168.225.78');
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(identifyBtn).onPressed,
      isNotNull,
    );
  });

  testWidgets('tapping Identify calls service and renders 7 channel cards',
      (tester) async {
    final service = _FakeService(_report(protocol: Protocol.escPos));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: service)));

    await tester.enterText(find.byType(TextField), '192.168.225.78');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    // Seven channel labels rendered.
    expect(find.text('ch1 ESC/POS probe'), findsOneWidget);
    expect(find.text('ch2 GS I'), findsOneWidget);
    expect(find.text('ch3 PJL'), findsOneWidget);
    expect(find.text('ch4 IPP'), findsOneWidget);
    expect(find.text('ch5 SNMP'), findsOneWidget);
    expect(find.text('ch6 HTTP'), findsOneWidget);
    expect(find.text('ch7 mDNS'), findsOneWidget);
  });

  testWidgets('"Send test receipt" visible only when ESC/POS confirmed',
      (tester) async {
    final escPos = _FakeService(_report(protocol: Protocol.escPos));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: escPos)));
    await tester.enterText(find.byType(TextField), '192.168.225.78');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();
    expect(find.text('Send test receipt'), findsOneWidget);

    final notEscPos = _FakeService(_report(
      protocol: Protocol.unknown,
      probeStatus: ChannelStatus.failed,
    ));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: notEscPos)));
    await tester.enterText(find.byType(TextField), '10.0.0.1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();
    expect(find.text('Send test receipt'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/pages/diagnose_page_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the page**

Create `app/lib/pages/diagnose_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

import '../services/printer_service.dart';
import '../widgets/channel_card.dart';
import '../widgets/device_info_panel.dart';
import '../widgets/print_test_dialog.dart';

class DiagnosePage extends StatefulWidget {
  final PrinterService service;
  const DiagnosePage({super.key, required this.service});

  @override
  State<DiagnosePage> createState() => _DiagnosePageState();
}

class _DiagnosePageState extends State<DiagnosePage> {
  final _ipCtrl = TextEditingController();
  static final _ipRegex = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  bool _deep = false;
  Future<IdentifyReport>? _pending;
  String? _lastIp;

  bool get _ipValid => _ipRegex.hasMatch(_ipCtrl.text.trim());

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  void _runIdentify() {
    final ip = _ipCtrl.text.trim();
    setState(() {
      _lastIp = ip;
      _pending = widget.service.identify(ip, deep: _deep);
    });
  }

  Future<void> _runPrintTest(String host) async {
    final enc = await showPrintTestDialog(context);
    if (enc == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await widget.service.printTest(host, enc);
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text('Sent $n bytes'),
      ));
    } on PrintTestException catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(e.message),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('printer_ip diagnose')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipCtrl,
              decoration: const InputDecoration(
                labelText: 'Printer IP',
                hintText: '192.168.0.10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Include invasive probes (PJL/ZPL)'),
              value: _deep,
              onChanged: (v) => setState(() => _deep = v ?? false),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _ipValid ? _runIdentify : null,
              child: const Text('Identify'),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResult()),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final pending = _pending;
    if (pending == null) {
      return const Center(child: Text('Enter an IP and tap Identify.'));
    }
    return FutureBuilder<IdentifyReport>(
      future: pending,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData) {
          // Cannot happen — identify never throws. Defensive only.
          return Center(child: Text('error: ${snap.error}'));
        }
        final report = snap.data!;
        final canPrint = report.escPosProbe.ok &&
            report.device.protocol == Protocol.escPos;
        return ListView(
          children: [
            DeviceInfoPanel(device: report.device),
            ChannelCard(
              label: 'ch1 ESC/POS probe',
              status: report.escPosProbe.status,
              elapsed: report.escPosProbe.elapsed,
              summary: report.escPosProbe.ok
                  ? 'protocol: ${report.escPosProbe.value!.protocol.name}'
                  : report.escPosProbe.error,
            ),
            ChannelCard(
              label: 'ch2 GS I',
              status: report.gsIdentity.status,
              elapsed: report.gsIdentity.elapsed,
              summary: report.gsIdentity.ok
                  ? '${report.gsIdentity.value!.manufacturer ?? '?'} / '
                      '${report.gsIdentity.value!.model ?? '?'}'
                  : report.gsIdentity.error,
            ),
            ChannelCard(
              label: 'ch3 PJL',
              status: report.pjl.status,
              elapsed: report.pjl.elapsed,
              summary: report.pjl.ok
                  ? report.pjl.value!.modelId ?? '(no model)'
                  : report.pjl.error,
            ),
            ChannelCard(
              label: 'ch4 IPP',
              status: report.ipp.status,
              elapsed: report.ipp.elapsed,
              summary: report.ipp.ok
                  ? report.ipp.value!.makeAndModel ?? '(no make/model)'
                  : report.ipp.error,
            ),
            ChannelCard(
              label: 'ch5 SNMP',
              status: report.snmp.status,
              elapsed: report.snmp.elapsed,
              summary: report.snmp.ok
                  ? report.snmp.value!.sysDescr ?? '(no sysDescr)'
                  : report.snmp.error,
            ),
            ChannelCard(
              label: 'ch6 HTTP',
              status: report.http.status,
              elapsed: report.http.elapsed,
              summary: report.http.ok
                  ? report.http.value!.title ?? '(no title)'
                  : report.http.error,
            ),
            ChannelCard(
              label: 'ch7 mDNS',
              status: report.mdns.status,
              elapsed: report.mdns.elapsed,
              summary: report.mdns.ok
                  ? report.mdns.value!.hostname ?? '(no hostname)'
                  : report.mdns.error,
            ),
            if (canPrint)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: () => _runPrintTest(_lastIp!),
                  child: const Text('Send test receipt'),
                ),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/pages/diagnose_page_test.dart`
Expected: `All tests passed!` (three tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/pages/diagnose_page.dart app/test/pages/diagnose_page_test.dart
git commit -m "DiagnosePage wires IP input + Identify + 7 channels + print-test"
```

---

## Task 8: `main.dart` + `app.dart` (no TDD — pure wiring)

**Files:**
- Overwrite: `app/lib/main.dart`
- Create: `app/lib/app.dart`

This task has no logic worth testing — just `runApp` + `MaterialApp` shell. Widget tests in Task 7 already cover the page.

- [ ] **Step 1: Overwrite `app/lib/main.dart`**

Replace its contents with:

```dart
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  runApp(const PrinterIpApp());
}
```

- [ ] **Step 2: Create `app/lib/app.dart`**

```dart
import 'package:flutter/material.dart';

import 'pages/diagnose_page.dart';
import 'services/printer_service.dart';

class PrinterIpApp extends StatelessWidget {
  const PrinterIpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'printer_ip diagnose',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: DiagnosePage(service: PrinterService()),
    );
  }
}
```

- [ ] **Step 3: Confirm `flutter test` is fully green**

Run: `cd app && flutter test`
Expected: All test files pass — smoke, three widget tests, service test, page test.

- [ ] **Step 4: Confirm static analysis is clean**

Run: `cd app && flutter analyze`
Expected: `No issues found!` If there are any unused imports or linter warnings, fix them.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart app/lib/app.dart
git commit -m "wire main.dart + PrinterIpApp shell"
```

---

## Task 9: Android cleartext + permissions

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`

The HTTP probe hits LAN POS printers on plain HTTP. Android 9+ blocks cleartext by default — `usesCleartextTraffic="true"` is mandatory.

- [ ] **Step 1: Read the current manifest**

Run: `cat app/android/app/src/main/AndroidManifest.xml`
Expected: a `<manifest>` with an `<application>` tag generated by `flutter create`.

- [ ] **Step 2: Add `usesCleartextTraffic` + `ACCESS_NETWORK_STATE`**

Edit `app/android/app/src/main/AndroidManifest.xml`:

1. Add `android:usesCleartextTraffic="true"` to the existing `<application>` tag (alongside `android:label`, `android:icon`, etc.).
2. Add this permission line **above** the `<application>` opening tag (alongside any existing `<uses-permission>` lines — there may already be an INTERNET one, which is fine):

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

(If `INTERNET` is already present, don't duplicate it.)

- [ ] **Step 3: Verify the manifest parses**

Run: `cd app && flutter analyze`
Expected: `No issues found!` Flutter analyze doesn't parse XML, but malformed XML breaks the next build step.

- [ ] **Step 4: Build the Android APK to verify the manifest**

Run: `cd app && flutter build apk --debug`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk.` If the manifest is malformed, this fails with an AAPT2 error.

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/AndroidManifest.xml
git commit -m "Android: cleartext HTTP + ACCESS_NETWORK_STATE for mDNS"
```

---

## Task 10: Manual verification on Windows + Android

This task is manual — no test code. Marks the project as done.

- [ ] **Step 1: Run on Windows against the lab printer**

Prereq: be on the lab subnet that can reach `192.168.225.78`. (Mac dev machine needs the VPN-bypass route; Windows on the LAN reaches it directly.)

Run: `cd app && flutter run -d windows`

In the running app:
1. Enter `192.168.225.78`. Verify the Identify button enables.
2. Leave "Include invasive probes" unchecked. Tap Identify.
3. Within ~3s, expect:
   - DeviceInfo panel shows `EPSON` / `TM-T88III` / `8.00 ESC/POS` / `E2QG064874`.
   - ch1 ESC/POS probe → green ✓
   - ch2 GS I → green ✓
   - ch3 PJL → grey – (skipped: not in deep mode)
   - ch4 IPP → red ✗ (`no IPP response`)
   - ch5 SNMP → red ✗ (`no SNMP response`)
   - ch6 HTTP → red ✗ (`TCP RST`)
   - ch7 mDNS → red ✗ (`no advertise`)
4. "Send test receipt" button is visible. Tap it.
5. In the dialog, switch from Big5 → **GBK** (the lab printer has GBK ROM; Big5 prints garbage on it). Tap Send.
6. Expect green snackbar "Sent N bytes" and a readable Chinese receipt printed.

If any of ch1+ch2 fail or the test receipt is garbled, capture the IdentifyReport summary and stop — the lib behavior diverged from the memory snapshot and needs investigation before claiming this complete.

- [ ] **Step 2: Run on Android against the same printer**

Same LAN — phone on Wi-Fi or USB tethered to the lab network.

Run: `cd app && flutter run -d <android-device-id>`

(Find the device id via `flutter devices`.)

Perform the same 6 steps as Windows. Expected: identical channel matrix and identical print result.

If the HTTP channel inexplicably succeeds on Android with a snackbar-style error like "Cleartext HTTP traffic not permitted", revisit Task 9 — the manifest patch didn't take effect (possibly cached APK; try `flutter clean && flutter run`).

- [ ] **Step 3: Update CLAUDE/README if needed**

If the manual run uncovered any non-obvious gotcha (a permission prompt sequence, a firewall step, a Windows-specific quirk), add a one-paragraph "Running the Flutter app" section to `README.md` documenting it. If nothing surprising came up, skip this step.

- [ ] **Step 4: Final commit (only if README updated)**

```bash
git add README.md
git commit -m "README: notes for running the Flutter app"
```

---

## Verification matrix (end-of-plan checklist)

Before declaring the plan done, all of these must be true. Tick them off:

- [ ] `cd app && flutter test` — all green, no skipped, no warnings.
- [ ] `cd app && flutter analyze` — `No issues found!`
- [ ] `cd app && flutter build apk --debug` — succeeds.
- [ ] `cd app && flutter build windows` — succeeds.
- [ ] Manual run on Windows against `192.168.225.78` produces the expected 7-channel matrix.
- [ ] Manual run on Android against the same target produces the same matrix.
- [ ] Test receipt prints readable Chinese with GBK encoding on the lab printer.
- [ ] Existing `dart test` at repo root still passes (library unchanged).
