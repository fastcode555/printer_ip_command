# 复制完整探测报告按钮 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `DiagnosePage` 上加一个复制按钮，把当前 `IdentifyReport`（DeviceInfo + 7 通道）一键复制为纯文本到剪贴板，并 snackbar 反馈。

**Architecture:** 新增纯函数 `formatReportAsText(IdentifyReport) → String` 放在 `services/report_formatter.dart`。`DeviceInfoPanel` 加可选 `onCopy` 回调（保持组件边界，不让它知道 IdentifyReport）。`DiagnosePage` 注入回调，调 `Clipboard.setData` + 弹绿色 snackbar。无新依赖。

**Tech Stack:** Flutter / Dart 3.6+，`package:flutter/services.dart` 的 `Clipboard` API。

**Spec reference:** `docs/superpowers/specs/2026-05-20-copy-report-design.md`

---

## File Structure

**Created:**
- `app/lib/services/report_formatter.dart` — 纯函数 `formatReportAsText`
- `app/test/services/report_formatter_test.dart` — formatter 单测

**Modified:**
- `app/lib/widgets/device_info_panel.dart` — 加可选 `onCopy` 参数 + 右上角 IconButton
- `app/test/widgets/device_info_panel_test.dart` — 加 1 case（onCopy 触发回调），现有 2 个 case 补 1 行断言（无 onCopy 时图标不渲染）
- `app/lib/pages/diagnose_page.dart` — `_buildResult` 给 DeviceInfoPanel 传 onCopy + 新增 `_copyReport(report)` 方法
- `app/test/pages/diagnose_page_test.dart` — 加 1 case（点复制 → 剪贴板写入 + snackbar 显示）

**Untouched:** 根 `lib/`、`bin/`、根 `pubspec.yaml`、Android/Windows 平台配置。

---

## Task 1: `report_formatter.dart`（TDD）

**Files:**
- Create: `app/lib/services/report_formatter.dart`
- Test: `app/test/services/report_formatter_test.dart`

- [ ] **Step 1: 写失败测试**

Create `app/test/services/report_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/services/report_formatter.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  test('formatReportAsText emits expected header + 7 channel lines', () {
    final report = IdentifyReport(
      host: '192.168.225.78',
      escPosProbe: const ChannelOutcome<ProbeResult>(
        status: ChannelStatus.success,
        elapsed: Duration(milliseconds: 1121),
      ),
      gsIdentity: const ChannelOutcome<EscPosIdentity>(
        status: ChannelStatus.success,
        elapsed: Duration(milliseconds: 831),
      ),
      pjl: const ChannelOutcome<PjlResult>(
        status: ChannelStatus.skipped,
        elapsed: Duration.zero,
        error: 'only runs with --deep',
      ),
      ipp: const ChannelOutcome<IppResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(milliseconds: 1024),
        error: 'no IPP response (port closed or path mismatch)',
      ),
      snmp: const ChannelOutcome<SnmpResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(milliseconds: 2006),
        error: 'no SNMP response (agent disabled or community mismatch)',
      ),
      http: const ChannelOutcome<HttpFingerprint>(
        status: ChannelStatus.failed,
        elapsed: Duration(milliseconds: 227),
        error: 'no HTTP banner (port closed or non-HTTP)',
      ),
      mdns: const ChannelOutcome<MdnsResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(milliseconds: 2029),
        error: 'no mDNS service matching this IP (device not advertising)',
      ),
      device: const DeviceInfo(
        host: '192.168.225.78',
        protocol: Protocol.escPos,
        vendor: 'EPSON',
        model: 'TM-T88III',
        firmware: '8.00 ESC/POS',
        serial: 'E2QG064874',
      ),
    );

    final text = formatReportAsText(report);

    // Header block: each field on its own line, em-dash for null.
    expect(text, contains('host            : 192.168.225.78'));
    expect(text, contains('protocol        : escPos'));
    expect(text, contains('vendor          : EPSON'));
    expect(text, contains('model           : TM-T88III'));
    expect(text, contains('firmware        : 8.00 ESC/POS'));
    expect(text, contains('serial          : E2QG064874'));
    expect(text, contains('mDNS hostname   : —'));
    expect(text, contains('formats         : —'));

    // Channels with status markers.
    expect(text, contains('ch1 ESC/POS probe'));
    expect(text, contains('[✓]'));
    expect(text, contains('ch3 PJL'));
    expect(text, contains('[-]'));
    expect(text, contains('ch4 IPP'));
    expect(text, contains('[✗]'));
    expect(text, contains('only runs with --deep'));
    expect(text, contains('no IPP response (port closed or path mismatch)'));

    // Channels appear in fixed order.
    final ch1 = text.indexOf('ch1 ESC/POS probe');
    final ch7 = text.indexOf('ch7 mDNS');
    expect(ch1 >= 0 && ch7 > ch1, isTrue);
  });

  test('formatReportAsText renders em-dash for empty document formats list', () {
    final report = IdentifyReport(
      host: '10.0.0.1',
      escPosProbe: const ChannelOutcome<ProbeResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(seconds: 2),
        error: 'timeout',
      ),
      gsIdentity: const ChannelOutcome<EscPosIdentity>(
        status: ChannelStatus.skipped,
        elapsed: Duration.zero,
        error: 'protocol is not ESC/POS',
      ),
      pjl: const ChannelOutcome<PjlResult>(
        status: ChannelStatus.skipped,
        elapsed: Duration.zero,
        error: 'skipped',
      ),
      ipp: const ChannelOutcome<IppResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(seconds: 2),
        error: 'timeout',
      ),
      snmp: const ChannelOutcome<SnmpResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(seconds: 2),
        error: 'timeout',
      ),
      http: const ChannelOutcome<HttpFingerprint>(
        status: ChannelStatus.failed,
        elapsed: Duration(seconds: 2),
        error: 'timeout',
      ),
      mdns: const ChannelOutcome<MdnsResult>(
        status: ChannelStatus.failed,
        elapsed: Duration(seconds: 2),
        error: 'timeout',
      ),
      device: const DeviceInfo(host: '10.0.0.1', protocol: Protocol.unknown),
    );

    final text = formatReportAsText(report);
    expect(text, contains('vendor          : —'));
    expect(text, contains('model           : —'));
    expect(text, contains('formats         : —'));
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && flutter test test/services/report_formatter_test.dart`
Expected: FAIL with `Error when reading 'lib/services/report_formatter.dart': No such file or directory`.

- [ ] **Step 3: 实现 formatter**

Create `app/lib/services/report_formatter.dart`:

```dart
import 'package:printer_ip_command/printer_ip_command.dart';

/// Render the full identify report as CLI-style plain text for clipboard copy.
String formatReportAsText(IdentifyReport report) {
  final device = report.device;
  final buf = StringBuffer();

  _kv(buf, 'host', device.host);
  _kv(buf, 'protocol', device.protocol.name);
  _kv(buf, 'vendor', device.vendor);
  _kv(buf, 'model', device.model);
  _kv(buf, 'firmware', device.firmware);
  _kv(buf, 'serial', device.serial);
  _kv(buf, 'mDNS hostname', device.mdnsHostname);
  _kv(buf, 'formats',
      device.documentFormats.isEmpty ? null : device.documentFormats.join(', '));

  buf.writeln();

  _channel(buf, 'ch1 ESC/POS probe', report.escPosProbe, () {
    final v = report.escPosProbe.value;
    return 'protocol: ${v?.protocol.name ?? '?'}';
  });
  _channel(buf, 'ch2 GS I', report.gsIdentity, () {
    final v = report.gsIdentity.value;
    return '${v?.manufacturer ?? '?'} / ${v?.model ?? '?'}';
  });
  _channel(buf, 'ch3 PJL', report.pjl, () {
    return report.pjl.value?.modelId ?? '(no model)';
  });
  _channel(buf, 'ch4 IPP', report.ipp, () {
    return report.ipp.value?.makeAndModel ?? '(no make/model)';
  });
  _channel(buf, 'ch5 SNMP', report.snmp, () {
    return report.snmp.value?.sysDescr ?? '(no sysDescr)';
  });
  _channel(buf, 'ch6 HTTP', report.http, () {
    return report.http.value?.title ?? '(no title)';
  });
  _channel(buf, 'ch7 mDNS', report.mdns, () {
    return report.mdns.value?.hostname ?? '(no hostname)';
  });

  return buf.toString();
}

void _kv(StringBuffer buf, String key, String? value) {
  final v = (value == null || value.isEmpty) ? '—' : value;
  buf.writeln('${key.padRight(16)}: $v');
}

void _channel(
  StringBuffer buf,
  String label,
  ChannelOutcome outcome,
  String Function() okSummary,
) {
  final marker = switch (outcome.status) {
    ChannelStatus.success => '✓',
    ChannelStatus.failed => '✗',
    ChannelStatus.skipped => '-',
  };
  final ms = outcome.elapsed.inMilliseconds.toString().padLeft(4);
  final summary =
      outcome.status == ChannelStatus.success ? okSummary() : outcome.error;
  buf.writeln('${label.padRight(20)} [$marker]   $ms ms   $summary');
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && flutter test test/services/report_formatter_test.dart`
Expected: `All tests passed!`（2 tests）

- [ ] **Step 5: 提交**

```bash
git add app/lib/services/report_formatter.dart app/test/services/report_formatter_test.dart
git commit -m "report_formatter: CLI-style text rendering of IdentifyReport"
```

---

## Task 2: `DeviceInfoPanel` 加可选 `onCopy` 参数（TDD）

**Files:**
- Modify: `app/lib/widgets/device_info_panel.dart`
- Modify: `app/test/widgets/device_info_panel_test.dart`

- [ ] **Step 1: 修改测试，加 onCopy case 并给现有 case 补回归断言**

Replace the entire `app/test/widgets/device_info_panel_test.dart` with:

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
    // onCopy is null → no copy icon
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });

  testWidgets('renders em-dash for null fields', (tester) async {
    const device = DeviceInfo(
      host: '10.0.0.1',
      protocol: Protocol.unknown,
    );

    await tester.pumpWidget(_wrap(const DeviceInfoPanel(device: device)));

    expect(find.text('—'), findsWidgets);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });

  testWidgets('onCopy non-null → copy icon renders and triggers callback',
      (tester) async {
    var tapped = false;
    const device = DeviceInfo(
      host: '192.168.225.78',
      protocol: Protocol.escPos,
    );

    await tester.pumpWidget(_wrap(DeviceInfoPanel(
      device: device,
      onCopy: () => tapped = true,
    )));

    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy_outlined));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试，确认 onCopy case 失败**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: 第三个 case FAIL（`onCopy` 参数未定义）。前两个 case 也可能因为 `Icons.copy_outlined` 引用而编译失败，那就是整个文件都不过 —— 都算预期。

- [ ] **Step 3: 修改 `DeviceInfoPanel`**

Replace the entire `app/lib/widgets/device_info_panel.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

class DeviceInfoPanel extends StatelessWidget {
  final DeviceInfo device;
  final VoidCallback? onCopy;

  const DeviceInfoPanel({super.key, required this.device, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Device',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    tooltip: '复制完整报告',
                    onPressed: onCopy,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
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

- [ ] **Step 4: 运行测试，确认全部通过**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: `All tests passed!`（3 tests）

- [ ] **Step 5: 提交**

```bash
git add app/lib/widgets/device_info_panel.dart app/test/widgets/device_info_panel_test.dart
git commit -m "DeviceInfoPanel: optional onCopy callback + copy icon"
```

---

## Task 3: `DiagnosePage` 接入复制 + Clipboard + snackbar（TDD）

**Files:**
- Modify: `app/lib/pages/diagnose_page.dart`
- Modify: `app/test/pages/diagnose_page_test.dart`

- [ ] **Step 1: 在 `diagnose_page_test.dart` 末尾追加一个新测试**

Add this `testWidgets(...)` block at the end of the existing `main()` in `app/test/pages/diagnose_page_test.dart`, just before the closing `}`:

```dart
  testWidgets('tapping copy icon writes formatted report to clipboard',
      (tester) async {
    final service = _FakeService(_report(protocol: Protocol.escPos));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: service)));

    await tester.enterText(find.byType(TextField), '192.168.225.78');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();

    // Mock the platform clipboard channel.
    String? capturedText;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        capturedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pumpAndSettle();

    expect(capturedText, isNotNull);
    expect(capturedText, contains('host            : 192.168.225.78'));
    expect(capturedText, contains('ch1 ESC/POS probe'));
    expect(find.text('已复制完整报告'), findsOneWidget);

    // Unhook the mock so it doesn't leak to other tests.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
```

Also add the required imports at the top of the same file (next to existing imports):

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: 运行测试，确认新 case 失败**

Run: `cd app && flutter test test/pages/diagnose_page_test.dart`
Expected: 4 个 case，新加的 FAIL（找不到 `Icons.copy_outlined` —— page 还没传 onCopy）。

- [ ] **Step 3: 修改 `DiagnosePage`**

In `app/lib/pages/diagnose_page.dart`:

(a) Add this import at the top, after `package:flutter/material.dart`:

```dart
import 'package:flutter/services.dart';
```

Also add this import after the existing `import '../widgets/print_test_dialog.dart';` line:

```dart
import '../services/report_formatter.dart';
```

(b) Find this line in `_buildResult`:

```dart
            DeviceInfoPanel(device: report.device),
```

Replace it with:

```dart
            DeviceInfoPanel(
              device: report.device,
              onCopy: () => _copyReport(report),
            ),
```

(c) Add a new private method to `_DiagnosePageState`, right after `_runPrintTest`:

```dart
  Future<void> _copyReport(IdentifyReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: formatReportAsText(report)),
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      backgroundColor: Colors.green.shade700,
      content: const Text('已复制完整报告'),
      duration: const Duration(seconds: 2),
    ));
  }
```

- [ ] **Step 4: 运行测试，确认全部通过**

Run: `cd app && flutter test test/pages/diagnose_page_test.dart`
Expected: `All tests passed!`（4 tests）

- [ ] **Step 5: 跑全量测试 + analyzer 守底**

Run: `cd app && flutter test`
Expected: 18 tests, all passed!（原 14 + 新 4：formatter 2 + panel 1 + page 1）

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add app/lib/pages/diagnose_page.dart app/test/pages/diagnose_page_test.dart
git commit -m "DiagnosePage: wire copy icon → Clipboard + 已复制完整报告 snackbar"
```

---

## Task 4: 手机端验证（手动）

可选，需要插上手机 + 在实验室 Wi-Fi 下。

- [ ] **Step 1: 重建并安装**

```bash
cd app
flutter build apk --debug
flutter install --debug -d AP4XUT4124003126
```

- [ ] **Step 2: 启动 + 跑 identify**

```bash
adb shell am start -n com.printerip.printer_ip_app/.MainActivity
```

在手机上：输入 `192.168.225.78` → Identify → 等绿色 DeviceInfo 出现。

- [ ] **Step 3: 点 DeviceInfo 右上角的复制图标**

期望：
- 绿色 snackbar `已复制完整报告` 出现，~2 秒后消失
- 用 adb 验证剪贴板内容：`adb shell cmd clipboard get-primary-clip-text`（华为 ROM 有时禁此命令，那就 paste 到 IM/邮件里看）
- 期望剪贴板内容含 `host            : 192.168.225.78` + `vendor          : EPSON` + 7 行 channel

- [ ] **Step 4: 合并到 main**

如果验证通过，按和上次特性一样的流程把分支合回 main 并清理 worktree。

---

## Verification matrix

跑完 Task 1-3 后，下面这些必须全部满足：

- [ ] `cd app && flutter test` → 18/18 passed
- [ ] `cd app && flutter analyze` → No issues found!
- [ ] formatter 输出的格式符合 spec 中 ASCII 表格示例的结构（key 列对齐到 16 字符、channel label 对齐到 20 字符、elapsed 数字 4 字符右对齐）
- [ ] DeviceInfoPanel 在 `onCopy: null` 时不渲染复制图标（回归）
- [ ] DiagnosePage 点复制图标 → 剪贴板被写入 + snackbar 显示 `已复制完整报告`
