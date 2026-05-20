# 探测中文 ROM 类型 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 `GS I 0x45` 查询打印机的 language ROM，把结果（`CHINA GB18030` / `HONG KONG BIG5` / etc）暴露到 `DeviceInfo.language`，再通过 `ChineseRom` enum 给上层路由（文字 vs 图片打印）用。UI、复制报告、CLI 都展示这个新信号。

**Architecture:** Lib 加 1 个新文件 (`chinese_rom.dart`，纯函数 enum + classifier) + 改 2 个文件（`escpos_identity.dart` 加 0x45 query/字段，`identifier.dart` 的 `DeviceInfo` 加字段）。App 改 2 个文件（DeviceInfoPanel + report_formatter 各加两行）。CLI 改 1 个文件（`bin/printer_probe.dart` 加 2 处字段渲染）。无新依赖。

**Tech Stack:** Dart 3.6（lib + CLI），Flutter 3.27+（app）。`package:test`（lib 单测）+ `flutter_test`（app widget 测试）。

**Spec reference:** `docs/superpowers/specs/2026-05-20-language-detection-design.md`

---

## File Structure

**Created:**
- `lib/src/chinese_rom.dart` — enum + classifier
- `test/chinese_rom_test.dart` — classifier 单元测试

**Modified (lib):**
- `lib/src/escpos_identity.dart` — `EscPosIdentity.language` 字段 + 第 5 个 GS I 0x45 query
- `lib/src/identifier.dart` — `DeviceInfo.language` 字段 + `mergeDeviceInfo` 写入
- `lib/printer_ip_command.dart` — 导出 `ChineseRom` 和 `classifyLanguage`
- `test/escpos_identity_test.dart` — 测试 parseGsIResponse 对 `CHINA GB18030` 格式的 case（已经能 work，验证而已）
- `test/identify_report_test.dart` — 模拟服务器加 0x45 响应段，断言 `device.language` 被填

**Modified (CLI):**
- `bin/printer_probe.dart` — `_printChannel2GsIdentity` 加 language 行；`_printAggregated` 加 language row

**Modified (app):**
- `app/lib/widgets/device_info_panel.dart` — 加两行 (language 原始 + Chinese ROM 语义化)
- `app/lib/services/report_formatter.dart` — 头部加两行
- `app/test/widgets/device_info_panel_test.dart` — 现有 case 加 language，断言两行渲染
- `app/test/services/report_formatter_test.dart` — 现有第一个 case 的 device 加 language，断言两行

**Untouched:** Android manifest、Windows scaffold、根 pubspec.yaml。

---

## Task 1: `chinese_rom.dart`（TDD，纯函数）

**Files:**
- Create: `lib/src/chinese_rom.dart`
- Test: `test/chinese_rom_test.dart`
- Modify: `lib/printer_ip_command.dart`（加 export）

- [ ] **Step 1: 写失败测试**

Create `test/chinese_rom_test.dart`:

```dart
import 'package:printer_ip_command/src/chinese_rom.dart';
import 'package:test/test.dart';

void main() {
  group('classifyLanguage', () {
    test('HONG KONG BIG5 → traditional', () {
      expect(classifyLanguage('HONG KONG BIG5'), ChineseRom.traditional);
    });

    test('TAIWAN BIG5 → traditional', () {
      expect(classifyLanguage('TAIWAN BIG5'), ChineseRom.traditional);
    });

    test('lowercase big5 → traditional (case insensitive)', () {
      expect(classifyLanguage('big5'), ChineseRom.traditional);
    });

    test('CHINA GB18030 → simplified', () {
      expect(classifyLanguage('CHINA GB18030'), ChineseRom.simplified);
    });

    test('CHINA GBK → simplified', () {
      expect(classifyLanguage('CHINA GBK'), ChineseRom.simplified);
    });

    test('bare GB string → simplified (prefix match)', () {
      expect(classifyLanguage('CHINA GB'), ChineseRom.simplified);
    });

    test('null → unknown', () {
      expect(classifyLanguage(null), ChineseRom.unknown);
    });

    test('empty string → unknown', () {
      expect(classifyLanguage(''), ChineseRom.unknown);
    });

    test('JAPAN JIS → unknown (other Asian languages)', () {
      expect(classifyLanguage('JAPAN JIS'), ChineseRom.unknown);
    });

    test('random gibberish → unknown', () {
      expect(classifyLanguage('foobar'), ChineseRom.unknown);
    });

    test('mixed BIG5 wins over GB (priority)', () {
      // Hypothetical string containing both — Big5 should win because it's
      // the more specific Traditional Chinese marker.
      expect(classifyLanguage('BIG5 GB INTL'), ChineseRom.traditional);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `dart test test/chinese_rom_test.dart`
Expected: 编译失败，`Error: Error when reading 'lib/src/chinese_rom.dart': No such file or directory`.

- [ ] **Step 3: 实现 classifier**

Create `lib/src/chinese_rom.dart`:

```dart
/// Coarse classification of a printer's Chinese character ROM, derived from
/// the GS I 0x45 ("font of language") query response. The raw string lives on
/// [DeviceInfo.language]; this enum is what business logic should branch on
/// when choosing text vs image print path.
enum ChineseRom {
  /// Traditional Chinese (HK/TW market). Caller can send Big5-encoded text.
  traditional,

  /// Simplified Chinese (mainland market). Caller can send GBK/GB18030 text.
  simplified,

  /// Anything else — printer didn't implement GS I 0x45, responded with
  /// empty string, or reported a non-Chinese ROM (JIS, KSC, etc). Caller
  /// must fall back to image printing to be safe.
  unknown,
}

/// Classify a raw GS I 0x45 response into a [ChineseRom] bucket.
///
/// Matching rules (case-insensitive, evaluated in order):
///   1. contains 'BIG5'  → traditional
///   2. contains 'GB'    → simplified
///   3. anything else (null, empty, non-Chinese ROMs) → unknown
ChineseRom classifyLanguage(String? raw) {
  if (raw == null) return ChineseRom.unknown;
  final upper = raw.toUpperCase();
  if (upper.contains('BIG5')) return ChineseRom.traditional;
  if (upper.contains('GB')) return ChineseRom.simplified;
  return ChineseRom.unknown;
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `dart test test/chinese_rom_test.dart`
Expected: `All tests passed!`（11 tests）

- [ ] **Step 5: 加 export**

Edit `lib/printer_ip_command.dart`. Find the line:

```dart
export 'src/escpos_identity.dart'
    show EscPosIdentity, parseGsIResponse, probeEscPosIdentity;
```

Add this line right after it (alphabetical-ish ordering):

```dart
export 'src/chinese_rom.dart' show ChineseRom, classifyLanguage;
```

- [ ] **Step 6: 跑全量 lib test，守底**

Run: `dart test`
Expected: 全部通过（原有的 + 11 个新增）。Pre-existing flake `test/identifier_test.dart` 'PrinterIdentifier.identify (integration) combines 9100 ESC/POS probe + 631 IPP into DeviceInfo' 偶尔失败（Broken pipe），重跑那个文件单独通过就是正常。如果其他测试失败，停下来报告。

- [ ] **Step 7: 提交**

```bash
git add lib/src/chinese_rom.dart test/chinese_rom_test.dart lib/printer_ip_command.dart
git commit -m "chinese_rom: ChineseRom enum + classifyLanguage(GS I 0x45 raw → bucket)"
```

---

## Task 2: `EscPosIdentity` + `queryEscPosIdentity` 加 0x45 query

**Files:**
- Modify: `lib/src/escpos_identity.dart`
- Modify: `test/escpos_identity_test.dart`

`queryEscPosIdentity` 当前实现是：一个 socket 上一次性发 4 个 GS I 查询 (65/66/67/68)，listen 直到 timeout，按 NUL 分段，pick 4 个字段。加第 5 个 query (0x45=69) 只要：
- 多发一条 `gsIQuery(69)`
- `EscPosIdentity` 加 `language` 字段，`pick(4)` 拿值
- `hasAny` getter 也要看 `language`
- `toString()` 加字段

- [ ] **Step 1: 修改测试，加 0x45 case**

Replace the entire `test/escpos_identity_test.dart` with:

```dart
import 'dart:typed_data';

import 'package:printer_ip_command/src/escpos_identity.dart';
import 'package:test/test.dart';

void main() {
  group('parseGsIResponse', () {
    test('Type A: NUL-terminated ASCII (no header)', () {
      // 'Xprinter\0' = 9 bytes
      final bytes = Uint8List.fromList([0x58, 0x70, 0x72, 0x69, 0x6E, 0x74, 0x65, 0x72, 0x00]);
      expect(parseGsIResponse(bytes), 'Xprinter');
    });

    test('Type B: 0x5F header + ASCII + NUL', () {
      // 0x5F 'TM-T88V' 0x00
      final bytes = Uint8List.fromList([0x5F, 0x54, 0x4D, 0x2D, 0x54, 0x38, 0x38, 0x56, 0x00]);
      expect(parseGsIResponse(bytes), 'TM-T88V');
    });

    test('GS I 0x45 sample: header + CHINA GB18030 + NUL', () {
      // Real bytes captured from TM-T88III 8.00 ESC/POS firmware via
      // `printf '\x1D\x49\x45' | nc 192.168.225.78 9100`:
      //   5f 43 48 49 4e 41 20 47 42 31 38 30 33 30 00
      // After parseGsIResponse strips the 0x5F header, expect 'CHINA GB18030'.
      final bytes = Uint8List.fromList([
        0x5F, 0x43, 0x48, 0x49, 0x4E, 0x41, 0x20,
        0x47, 0x42, 0x31, 0x38, 0x30, 0x33, 0x30, 0x00,
      ]);
      expect(parseGsIResponse(bytes), 'CHINA GB18030');
    });

    test('returns null when bytes are empty', () {
      expect(parseGsIResponse(Uint8List(0)), isNull);
    });

    test('returns null when only NUL', () {
      expect(parseGsIResponse(Uint8List.fromList([0x00])), isNull);
    });

    test('strips trailing NUL even without explicit terminator inside buffer', () {
      // Some printers send data without trailing NUL — accept that too.
      final bytes = Uint8List.fromList('EPSON'.codeUnits);
      expect(parseGsIResponse(bytes), 'EPSON');
    });

    test('rejects non-printable garbage as null', () {
      final bytes = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(parseGsIResponse(bytes), isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认新加的 0x45 case 失败**

Run: `dart test test/escpos_identity_test.dart`
Expected: 现有 cases 通过，新加的 'GS I 0x45 sample' 通过（因为 parseGsIResponse 已经支持 Type B），但是 — 实际上这个测试**应该一次就过**，因为 `parseGsIResponse` 现在就能 parse。这个 case 是 documentation / regression 保护，不是 TDD-failing 测试。把它当作 Step 1 的一部分。

实际 TDD-failing 的部分是后面要加的 — EscPosIdentity 加 `language` 字段。我们当前没有针对 `queryEscPosIdentity` 完整流程的 unit test（只测 parseGsIResponse），所以 Step 1 的 parse 测试通过即代表 lib 已经能正确解析。

继续 Step 3 修改 `EscPosIdentity` 数据类 + `queryEscPosIdentity`。Step 2 仅为 sanity：现有测试全过。

- [ ] **Step 3: 修改 `EscPosIdentity` 数据类**

Edit `lib/src/escpos_identity.dart`. Replace the entire `EscPosIdentity` class (lines 5-19) with:

```dart
class EscPosIdentity {
  final String? firmware;       // GS I 65
  final String? manufacturer;   // GS I 66
  final String? model;          // GS I 67
  final String? serial;         // GS I 68
  final String? language;       // GS I 69 (0x45) — "font of language" ROM

  const EscPosIdentity({
    this.firmware,
    this.manufacturer,
    this.model,
    this.serial,
    this.language,
  });

  bool get hasAny =>
      firmware != null ||
      manufacturer != null ||
      model != null ||
      serial != null ||
      language != null;

  @override
  String toString() =>
      'EscPosIdentity(mfr: $manufacturer, model: $model, fw: $firmware, '
      'sn: $serial, lang: $language)';
}
```

- [ ] **Step 4: 修改 `queryEscPosIdentity` 加第 5 个 query**

Edit `lib/src/escpos_identity.dart`. Find these 4 lines:

```dart
  socket.add(gsIQuery(65));
  socket.add(gsIQuery(66));
  socket.add(gsIQuery(67));
  socket.add(gsIQuery(68));
```

Replace with:

```dart
  socket.add(gsIQuery(65));
  socket.add(gsIQuery(66));
  socket.add(gsIQuery(67));
  socket.add(gsIQuery(68));
  socket.add(gsIQuery(69)); // 0x45: font of language (Big5 / GBK / ...)
```

And find the return statement at the bottom of `queryEscPosIdentity`:

```dart
  return EscPosIdentity(
    firmware: pick(0),
    manufacturer: pick(1),
    model: pick(2),
    serial: pick(3),
  );
```

Replace with:

```dart
  return EscPosIdentity(
    firmware: pick(0),
    manufacturer: pick(1),
    model: pick(2),
    serial: pick(3),
    language: pick(4),
  );
```

- [ ] **Step 5: 跑 lib 测试**

Run: `dart test`
Expected: 全部通过。新加的 EscPosIdentity 字段不破坏现有测试（已有测试不构造 EscPosIdentity 实例直接断言字段）。

- [ ] **Step 6: 提交**

```bash
git add lib/src/escpos_identity.dart test/escpos_identity_test.dart
git commit -m "EscPosIdentity: language field + GS I 0x45 query"
```

---

## Task 3: `DeviceInfo` + `mergeDeviceInfo` 加 language 字段

**Files:**
- Modify: `lib/src/identifier.dart`
- Modify: `test/identify_report_test.dart`

- [ ] **Step 1: 修改测试，给现有 mock server 加 0x45 响应**

Edit `test/identify_report_test.dart`. Find the GS I mock server block:

```dart
        } else {
          // GS I connection: reply in GS I 65/66/67/68 order
          socket.listen((_) {});
          await Future<void>.delayed(const Duration(milliseconds: 20));
          socket.add('FW1'.codeUnits + [0x00]);       // 65 firmware
          socket.add('Xprinter'.codeUnits + [0x00]);  // 66 manufacturer
          socket.add('XP-T80A'.codeUnits + [0x00]);   // 67 model
          socket.add('SN1'.codeUnits + [0x00]);       // 68 serial
          await socket.flush();
          await socket.close();
        }
```

Replace with:

```dart
        } else {
          // GS I connection: reply in GS I 65/66/67/68/69 order
          socket.listen((_) {});
          await Future<void>.delayed(const Duration(milliseconds: 20));
          socket.add('FW1'.codeUnits + [0x00]);            // 65 firmware
          socket.add('Xprinter'.codeUnits + [0x00]);       // 66 manufacturer
          socket.add('XP-T80A'.codeUnits + [0x00]);        // 67 model
          socket.add('SN1'.codeUnits + [0x00]);            // 68 serial
          socket.add('CHINA GB18030'.codeUnits + [0x00]);  // 69 (0x45) language
          await socket.flush();
          await socket.close();
        }
```

Then find the first test's assertion block (the `expect` calls after `final report = await PrinterIdentifier.identify(...)`). After the existing assertions on `report.device.firmware` / `manufacturer` / `model` / `serial`, add:

```dart
      expect(report.device.language, 'CHINA GB18030');
```

If you can't find an obvious place — read the file to identify which test asserts `device` field shape, and add it there. There should be exactly one test that asserts these fields per the file structure.

- [ ] **Step 2: 运行测试，确认 language 断言失败**

Run: `dart test test/identify_report_test.dart`
Expected: 'successful 9100 probe + IPP yields per-channel SUCCESS' 测试 FAIL，因为 `report.device.language` 字段还不存在或为 null。

- [ ] **Step 3: 修改 `DeviceInfo` 数据类**

Edit `lib/src/identifier.dart`. Find the `DeviceInfo` class (around line 32-72) and replace it entirely with:

```dart
class DeviceInfo {
  final String host;
  final Protocol protocol;
  final String? vendor;
  final String? model;
  final String? firmware;
  final String? serial;
  final String? language;
  final String? makeAndModel;
  final String? sysDescr;
  final String? sysName;
  final String? mdnsHostname;
  final List<String> mdnsServices;
  final EscPosStatus? escPosStatus;
  final int? ippState;
  final List<String> documentFormats;

  const DeviceInfo({
    required this.host,
    required this.protocol,
    this.vendor,
    this.model,
    this.firmware,
    this.serial,
    this.language,
    this.makeAndModel,
    this.sysDescr,
    this.sysName,
    this.mdnsHostname,
    this.mdnsServices = const [],
    this.escPosStatus,
    this.ippState,
    this.documentFormats = const [],
  });

  @override
  String toString() => 'DeviceInfo('
      'host: $host, protocol: $protocol, vendor: $vendor, model: $model, '
      'firmware: $firmware, serial: $serial, language: $language, '
      'makeAndModel: $makeAndModel, sysDescr: $sysDescr, sysName: $sysName, '
      'escPosStatus: $escPosStatus, ippState: $ippState, '
      'documentFormats: $documentFormats)';
}
```

- [ ] **Step 4: 修改 `mergeDeviceInfo`**

Edit `lib/src/identifier.dart`. Find `mergeDeviceInfo` (around line 98). After the `final serial = ...` line and before the `final mergedFormats = ...` line, add:

```dart
  final language = identity?.language;
```

Then in the `return DeviceInfo(...)` block, add the `language: language,` line. The full updated return should look like:

```dart
  return DeviceInfo(
    host: host,
    protocol: protocol,
    vendor: vendor,
    model: model,
    firmware: identity?.firmware,
    serial: serial,
    language: language,
    makeAndModel: ipp?.makeAndModel,
    sysDescr: snmp?.sysDescr,
    sysName: snmp?.sysName,
    mdnsHostname: mdns?.hostname,
    mdnsServices: mdns?.services ?? const [],
    escPosStatus: probe?.status,
    ippState: ipp?.state,
    documentFormats: mergedFormats,
  );
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `dart test test/identify_report_test.dart`
Expected: 全部通过。

- [ ] **Step 6: 跑全量 lib test**

Run: `dart test`
Expected: 全部通过（除已知 flake — pre-existing test/identifier_test.dart 'combines 9100 ESC/POS probe + 631 IPP into DeviceInfo'，如果失败单独跑一次确认）。

- [ ] **Step 7: 提交**

```bash
git add lib/src/identifier.dart test/identify_report_test.dart
git commit -m "DeviceInfo: language field + mergeDeviceInfo passes through from identity"
```

---

## Task 4: CLI `bin/printer_probe.dart` 加 language 输出

**Files:**
- Modify: `bin/printer_probe.dart`

CLI 无单元测试，是手动验证（跑命令看输出）。

- [ ] **Step 1: 修改 `_printChannel2GsIdentity` 加 language 行**

Edit `bin/printer_probe.dart`. Find this function (around line 131):

```dart
void _printChannel2GsIdentity(IdentifyReport report, int rawPort) {
  final ch = report.gsIdentity;
  print('[2/7] ESC/POS GS I identity          (TCP $rawPort)');
  print('      Commands: GS I 65/66/67/68 → firmware, manufacturer, model, serial');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final id = ch.value!;
    print('      firmware         : ${id.firmware ?? "(none)"}');
    print('      manufacturer     : ${id.manufacturer ?? "(none)"}');
    print('      model            : ${id.model ?? "(none)"}');
    print('      serial           : ${id.serial ?? "(none)"}');
  } else if (ch.status == ChannelStatus.skipped) {
    print('      (skipped — only runs when 9100 probe returns ESC/POS)');
  }
  print('');
}
```

Replace with:

```dart
void _printChannel2GsIdentity(IdentifyReport report, int rawPort) {
  final ch = report.gsIdentity;
  print('[2/7] ESC/POS GS I identity          (TCP $rawPort)');
  print('      Commands: GS I 65/66/67/68/69 → firmware, manufacturer, model, serial, language');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final id = ch.value!;
    print('      firmware         : ${id.firmware ?? "(none)"}');
    print('      manufacturer     : ${id.manufacturer ?? "(none)"}');
    print('      model            : ${id.model ?? "(none)"}');
    print('      serial           : ${id.serial ?? "(none)"}');
    print('      language         : ${id.language ?? "(none)"}');
  } else if (ch.status == ChannelStatus.skipped) {
    print('      (skipped — only runs when 9100 probe returns ESC/POS)');
  }
  print('');
}
```

- [ ] **Step 2: 修改 `_printAggregated` 加 language row**

Edit `bin/printer_probe.dart`. Find `_printAggregated` (around line 227). Find this line:

```dart
  _row('serial',        d.serial,        source: _serialSource(report, d));
```

Add right after it:

```dart
  _row('language',      d.language,      source: report.gsIdentity.ok && d.language != null ? 'ch2: GS I 69 (0x45)' : '(none)');
```

- [ ] **Step 3: 验证 CLI 文件编译 + 测试守底**

Run: `dart analyze bin/printer_probe.dart`
Expected: `No issues found!`

Run: `dart test`
Expected: 全部通过（lib 没变，CLI 改动不影响 lib 测试）。

- [ ] **Step 4: 提交**

```bash
git add bin/printer_probe.dart
git commit -m "printer_probe CLI: render language in ch2 GS I + aggregated DeviceInfo"
```

---

## Task 5: `DeviceInfoPanel` 加两行（TDD）

**Files:**
- Modify: `app/lib/widgets/device_info_panel.dart`
- Modify: `app/test/widgets/device_info_panel_test.dart`

- [ ] **Step 1: 修改测试，加 language + Chinese ROM 断言**

Edit `app/test/widgets/device_info_panel_test.dart`. Replace the first test ('renders vendor / model / firmware / serial') with the version below — given the same DeviceInfo but with `language: 'CHINA GB18030'`, and asserting the two new rows render:

Replace this block:

```dart
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
```

With:

```dart
  testWidgets('renders vendor / model / firmware / serial / language / Chinese ROM',
      (tester) async {
    const device = DeviceInfo(
      host: '192.168.225.78',
      protocol: Protocol.escPos,
      vendor: 'EPSON',
      model: 'TM-T88III',
      firmware: '8.00 ESC/POS',
      serial: 'E2QG064874',
      language: 'CHINA GB18030',
    );

    await tester.pumpWidget(_wrap(const DeviceInfoPanel(device: device)));

    expect(find.text('EPSON'), findsOneWidget);
    expect(find.text('TM-T88III'), findsOneWidget);
    expect(find.text('8.00 ESC/POS'), findsOneWidget);
    expect(find.text('E2QG064874'), findsOneWidget);
    expect(find.text('192.168.225.78'), findsOneWidget);
    expect(find.text('escPos'), findsOneWidget);
    // New rows: raw language + classified Chinese ROM
    expect(find.text('CHINA GB18030'), findsOneWidget);
    expect(find.text('简体 (GBK)'), findsOneWidget);
    // onCopy is null → no copy icon
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
```

- [ ] **Step 2: 运行测试，确认新断言失败**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: 第一个 test FAIL，找不到 `CHINA GB18030` 或 `简体 (GBK)`。

- [ ] **Step 3: 修改 `DeviceInfoPanel` 渲染两行**

Edit `app/lib/widgets/device_info_panel.dart`. Find the `build` method's column children list. After:

```dart
            _row('mDNS hostname', device.mdnsHostname),
```

Add:

```dart
            _row('language', device.language),
            _row('Chinese ROM', _chineseRomText(classifyLanguage(device.language))),
```

Also add this private helper at the end of the class (right before the closing `}` of `DeviceInfoPanel`):

```dart
  String _chineseRomText(ChineseRom rom) {
    return switch (rom) {
      ChineseRom.traditional => '繁体 (Big5)',
      ChineseRom.simplified => '简体 (GBK)',
      ChineseRom.unknown => '未知',
    };
  }
```

The existing `import 'package:printer_ip_command/printer_ip_command.dart';` at the top already brings in `ChineseRom` and `classifyLanguage` (Task 1 added them to the lib's main export).

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && flutter test test/widgets/device_info_panel_test.dart`
Expected: `All tests passed!`（3 tests still — the new assertions are in the existing first test, no new test count）

- [ ] **Step 5: 跑全量 app test**

Run: `cd app && flutter test`
Expected: 全部通过。

注意：`report_formatter_test.dart` 现有 case 的 device 没有 `language` 字段，formatter 渲染 `language: —` + `Chinese ROM: 未知` — 不会破坏断言（现有断言是 `contains('...')`，不要求精确匹配）。但 Task 6 会扩充这些断言。

- [ ] **Step 6: 提交**

```bash
git add app/lib/widgets/device_info_panel.dart app/test/widgets/device_info_panel_test.dart
git commit -m "DeviceInfoPanel: render language + 中文 ROM 语义化两行"
```

---

## Task 6: `report_formatter.dart` 加两行（TDD）

**Files:**
- Modify: `app/lib/services/report_formatter.dart`
- Modify: `app/test/services/report_formatter_test.dart`

- [ ] **Step 1: 修改测试，加 language 到 canned report + 加断言**

Edit `app/test/services/report_formatter_test.dart`. In the first test (`'formatReportAsText emits expected header + 7 channel lines'`), find the `device:` field in the canned `IdentifyReport`:

```dart
      device: DeviceInfo(
        host: '192.168.225.78',
        protocol: Protocol.escPos,
        vendor: 'EPSON',
        model: 'TM-T88III',
        firmware: '8.00 ESC/POS',
        serial: 'E2QG064874',
      ),
```

Replace with:

```dart
      device: DeviceInfo(
        host: '192.168.225.78',
        protocol: Protocol.escPos,
        vendor: 'EPSON',
        model: 'TM-T88III',
        firmware: '8.00 ESC/POS',
        serial: 'E2QG064874',
        language: 'CHINA GB18030',
      ),
```

Then find the existing header-block assertions inside the same test:

```dart
    expect(text, contains('mDNS hostname   : —'));
    expect(text, contains('formats         : —'));
```

Replace with:

```dart
    expect(text, contains('mDNS hostname   : —'));
    expect(text, contains('language        : CHINA GB18030'));
    expect(text, contains('Chinese ROM     : 简体 (GBK)'));
    expect(text, contains('formats         : —'));
```

The second test (`'renders em-dash for empty document formats list'`) does not pass `language`, so formatter should render `language: —` + `Chinese ROM: 未知`. Add assertions for this in the second test, right before the existing `formats` assertion:

```dart
    expect(text, contains('language        : —'));
    expect(text, contains('Chinese ROM     : 未知'));
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd app && flutter test test/services/report_formatter_test.dart`
Expected: 两个 test 都 FAIL，找不到新加的 contains 断言。

- [ ] **Step 3: 修改 `report_formatter.dart` 加两行**

Edit `app/lib/services/report_formatter.dart`. Find the header block in `formatReportAsText`:

```dart
  _kv(buf, 'mDNS hostname', device.mdnsHostname);
  _kv(buf, 'formats',
      device.documentFormats.isEmpty ? null : device.documentFormats.join(', '));
```

Replace with:

```dart
  _kv(buf, 'mDNS hostname', device.mdnsHostname);
  _kv(buf, 'language', device.language);
  _kv(buf, 'Chinese ROM', _chineseRomText(classifyLanguage(device.language)));
  _kv(buf, 'formats',
      device.documentFormats.isEmpty ? null : device.documentFormats.join(', '));
```

Then add a private helper at the bottom of the file (after the existing `_channel` helper):

```dart
String _chineseRomText(ChineseRom rom) {
  return switch (rom) {
    ChineseRom.traditional => '繁体 (Big5)',
    ChineseRom.simplified => '简体 (GBK)',
    ChineseRom.unknown => '未知',
  };
}
```

The existing `import 'package:printer_ip_command/printer_ip_command.dart';` at the top brings in `ChineseRom` and `classifyLanguage`.

- [ ] **Step 4: 运行测试，确认通过**

Run: `cd app && flutter test test/services/report_formatter_test.dart`
Expected: `All tests passed!`（2 tests）

- [ ] **Step 5: 跑全量 app test + analyzer 守底**

Run: `cd app && flutter test`
Expected: 18 tests, all passed!

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add app/lib/services/report_formatter.dart app/test/services/report_formatter_test.dart
git commit -m "report_formatter: 头部加 language + Chinese ROM 两行"
```

---

## Task 7: 手机端验证（手动）

可选，需要手机连 USB + 在实验室 Wi-Fi 下。

- [ ] **Step 1: 重建 + 安装到手机**

```bash
cd app
flutter build apk --debug
flutter install --debug -d AP4XUT4124003126
```

- [ ] **Step 2: 启动**

```bash
adb shell am force-stop com.printerip.printer_ip_app
adb shell am start -n com.printerip.printer_ip_app/.MainActivity
```

在手机上：输入 `192.168.225.78` → Identify。

- [ ] **Step 3: 验证 DeviceInfo 面板新两行**

期望看到：
- `language        CHINA GB18030`
- `Chinese ROM     简体 (GBK)`

- [ ] **Step 4: 验证复制功能含新两行**

点 DeviceInfo 右上角复制图标，粘贴出来期望含：
```
host            : 192.168.225.78
protocol        : escPos
vendor          : EPSON
model           : TM-T88III
firmware        : 8.00 ESC/POS
serial          : E2QG064874
mDNS hostname   : —
language        : CHINA GB18030
Chinese ROM     : 简体 (GBK)
formats         : —

ch1 ...
...
```

- [ ] **Step 5: 跑一次 CLI 验证（可选，从 worktree 根）**

如果 Mac 能连到 192.168.225.78（前面发现可能不能，跳过即可）：

```bash
dart run bin/printer_probe.dart 192.168.225.78
```

期望 `[2/7] ESC/POS GS I identity` 块多一行 `language : CHINA GB18030`，`Aggregated DeviceInfo` 块多一行 `language : CHINA GB18030 ← ch2: GS I 69 (0x45)`。

如果 Mac 不在 LAN 上，跳过这一步 — CLI 用法已经手动确认过逻辑没问题（lib 测试覆盖了）。

---

## Verification matrix

跑完 Task 1-6 后，下面这些必须全部满足：

- [ ] `dart test` → 全部通过（pre-existing identifier_test integration flake 除外）
- [ ] `dart analyze` → 干净
- [ ] `cd app && flutter test` → 18/18 passed
- [ ] `cd app && flutter analyze` → No issues found!
- [ ] `lib/printer_ip_command.dart` 导出 `ChineseRom` + `classifyLanguage`
- [ ] DeviceInfo 面板 + 复制报告各渲染 `language` + `Chinese ROM` 两行
- [ ] CLI ch2 GS I 块输出含 `language` 行；Aggregated DeviceInfo 块输出含 `language` row
