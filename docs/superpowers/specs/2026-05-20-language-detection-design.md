# 探测打印机中文 ROM 类型（Big5 / GBK / 未知） — 设计

**日期：** 2026-05-20
**状态：** 已批准（待 spec review）

## 目标

不通过实际打印，仅靠 ESC/POS 协议探测，识别目标打印机的中文字库 ROM 类型，让上层业务可以路由：
- ROM 支持目标编码 → 走文字打印（快、内存小）
- ROM 不匹配 → 走图片打印（慢，但可保证正确字形）

新增信号通过现有的 ch2 GS I 通道扩展，最终落到 `DeviceInfo.language`（原始字符串）+ 解析出 `ChineseRom` enum 暴露给上层。UI 在 DeviceInfo 面板和复制报告里展示两行：原始字符串 + 语义化文案。

## 探测方法

**`GS I 0x45`** —— Epson 扩展 ID 查询，返回 NUL-terminated ASCII 字符串描述打印机的语言 ROM。在 TM-T88III 8.00 ESC/POS 实测确认（2026-05-20，从手机 adb shell 发命令）：

```
$ printf '\x1D\x49\x45' | nc 192.168.225.78 9100 | od -An -tx1
 5f 43 48 49 4e 41 20 47 42 31 38 30 33 30 00
                       _ C H I N A   G B 1 8 0 3 0 NUL
```

= `"_CHINA GB18030"`，与 `[[test-printer-identity]]` 记录的"GBK ROM"一致。

**返回格式与现有 0x41-0x44 一致**：NUL 终止 ASCII，可以复用现有 `parseGsIResponse` 解析逻辑。

**已知字符串约定**（从 Epson 文档 + 跨设备观察）：
- `_CHINA GB18030` / `_CHINA GBK` → 简体（GB18030 是 GBK 超集，归为同一档）
- `_HONG KONG BIG5` / `_TAIWAN BIG5` → 繁体
- `_JAPAN ...` / `_KOREA ...` → 其他亚洲语言（classifier 归 unknown）
- `""`（空字符串） → 纯 ASCII 打印机，无中文 ROM（classifier 归 unknown）
- 命令无响应 → 老 firmware / clone 不实现 0x45（classifier 归 unknown）

## 架构

仍是 lib 主导 + UI 渲染。新加一个 enum 解析器放在 lib 里，让 CLI 和 Flutter app 都能复用。

```
lib/src/
├── escpos_identity.dart          ← 加 0x45 查询 + EscPosIdentity.language 字段
├── identifier.dart                ← DeviceInfo 加 language 字段
└── chinese_rom.dart             ← NEW: ChineseRom enum + classifyLanguage()

app/lib/
├── widgets/device_info_panel.dart ← DeviceInfo 面板加两行
└── services/report_formatter.dart ← 复制报告头部加两行
```

## 组件契约

### `lib/src/chinese_rom.dart`（新）

```dart
enum ChineseRom { traditional, simplified, unknown }

/// Classify the raw GS I 0x45 response into a coarse ROM bucket.
/// - traditional: contains 'BIG5' (case-insensitive)
/// - simplified:  contains 'GB' or 'GBK' (case-insensitive)
/// - unknown:     anything else (null, empty string, non-Chinese ROMs,
///                clones that don't implement 0x45, garbage strings)
ChineseRom classifyLanguage(String? raw);
```

匹配优先级：先 BIG5（避免某些字符串同时含 BIG5 和 GB 时归错档）→ GB/GBK → 其他一律 unknown。空字符串和 null 都进 unknown（用户不需要区分"打印机明确说无 ROM"和"打印机不认 0x45"两种状态）。

### `lib/src/escpos_identity.dart` 修改

`EscPosIdentity` 加字段：

```dart
class EscPosIdentity {
  final String? manufacturer;  // 0x42
  final String? model;          // 0x43
  final String? firmware;       // 0x41
  final String? serial;         // 0x44
  final String? language;       // 0x45 ← NEW
  // ...
}
```

`probeEscPosIdentity` 内部串行查询 0x41, 0x42, 0x43, 0x44, **0x45**。每个 query 是独立的 socket 连接（与现有保持一致，避免 ESC/POS firmware 在单连接里返回多个混合响应）。0x45 失败时（timeout 或空响应）`language` 设为 null，不影响其他字段。

### `lib/src/identifier.dart` 修改

`DeviceInfo` 加字段：

```dart
class DeviceInfo {
  // ...existing fields...
  final String? language;       // ← NEW, source: identity.language
  // ...
}
```

`mergeDeviceInfo` 把 `identity?.language` 写进 `DeviceInfo.language`。

`toString()` 输出加 `language: ...` 字段，CLI 自动受益。

### `app/lib/widgets/device_info_panel.dart` 修改

在 `mDNS hostname` 行下方加两行：

```
language        : _CHINA GB18030
Chinese ROM     : 简体 (GBK)
```

- `language` 行：直显 `device.language`（null/空 → `—`）
- `Chinese ROM` 行：调 `classifyLanguage(device.language)`，映射到中文文案：
  - `traditional` → `繁体 (Big5)`
  - `simplified` → `简体 (GBK)`
  - `unknown` → `未知`

复用现有 `_row(label, value)` helper。新增一个 `_chineseRomText(ChineseRom)` 私有 helper 做 enum → 中文文案映射。

### `app/lib/services/report_formatter.dart` 修改

头部 `formats` 行之前加两行（保持和 DeviceInfo 面板字段顺序一致）：

```
language        : _CHINA GB18030
Chinese ROM     : 简体 (GBK)
```

文案规则同 UI。新增 `_chineseRomText(ChineseRom)` 私有 helper（同 UI 那个，逻辑短小，复制一份不抽共享 — YAGNI）。

### `bin/printer_probe.dart`：取决于 CLI 当前输出方式

需要先看 CLI 的实际输出代码：
- 如果 CLI 是 `print(device.toString())`（单行 dump）— 那必须把 `language` 加进 `DeviceInfo.toString()`（lib 改动的一部分）。CLI 文件本身 0 改动。
- 如果 CLI 是逐字段 format（多行人类可读）— 那要在 CLI 里加 `language` 字段渲染行，并且文案与 UI/复制报告对齐。

由 implementer 在 Task 1 开始时读一下 `bin/printer_probe.dart` 决定哪种路径。两种都不大，几行代码。

## 数据流

```
PrinterProbe.probe (ch1 ESC/POS) → confirms escPos
   │
   ▼
probeEscPosIdentity (ch2 GS I) → 5 个 socket round-trip:
   GS I 0x41 → firmware
   GS I 0x42 → manufacturer
   GS I 0x43 → model
   GS I 0x44 → serial
   GS I 0x45 → language        ← NEW
   │
   ▼
EscPosIdentity { firmware, manufacturer, model, serial, language }
   │
   ▼
mergeDeviceInfo → DeviceInfo.language = identity.language
   │
   ├── UI: DeviceInfoPanel → 2 行 (language 原始 + Chinese ROM 语义化)
   ├── 复制: report_formatter → 同 2 行
   └── CLI: bin/printer_probe.dart → toString() 自动包含
```

## 错误处理

- 0x45 在某些 clone / 老 firmware 上不响应：超时 2s 后 language = null。其他字段不影响。
- 响应字符串异常（非 ASCII / 含控制字符）：raw string 直存，分类器返回 `unknown`。
- 上层业务可以根据 `ChineseRom.unknown` 选择"保守降级到图片打印"。

## 测试

### 新增

**`test/chinese_rom_test.dart`** — `classifyLanguage` 单元测试，覆盖：
- `'_HONG KONG BIG5'` → traditional
- `'_TAIWAN BIG5'` → traditional
- `'_CHINA GB18030'` → simplified
- `'_CHINA GBK'` → simplified
- `'_CHINA GB'` → simplified（确认前缀匹配）
- `''`（空字符串） → unknown
- `null` → unknown
- `'_JAPAN JIS'` → unknown
- `'random gibberish'` → unknown
- `'big5'`（小写） → traditional（确认大小写不敏感）

### 扩充

**`test/escpos_identity_test.dart`** — 加 1 case：`probeEscPosIdentity` 完整查询包含 0x45，mock socket 按顺序返回 5 个响应，断言 `EscPosIdentity.language` 被填。

**`test/identify_report_test.dart`** — 加 1 case：成功 ESC/POS + identity 含 language → `report.device.language` 非 null。

**`app/test/widgets/device_info_panel_test.dart`** — 现有第一个 case（vendor/model/firmware/serial 完整）补一行 `language: '_CHINA GB18030'`，断言 UI 渲染 `_CHINA GB18030` + `简体 (GBK)` 两行。

**`app/test/services/report_formatter_test.dart`** — 现有第一个 case（成功路径）的 device 加 `language: '_CHINA GB18030'`，断言 text 含 `language        : _CHINA GB18030` + `Chinese ROM     : 简体 (GBK)`。

## Non-goals

- 不动 ch2 GS I 的 channel card summary（保持 `EPSON / TM-T88III`） — 卡片空间有限，新信息走 DeviceInfo 面板。
- 不做 UI 颜色 / 警告提示。`unknown` 仅文案。
- 不做"自动路由文字 vs 图片打印" — 是业务上层的事，本特性只把信号暴露出来。
- 不做跨厂商的 language 字符串归一化（不把 `_CHINA GB18030` 改成 `Chinese (GBK)` 之类）。原始字符串直显，让用户可以看到打印机自报的原文。

## 影响范围

- Lib：3 个文件改动（1 新增 + 2 修改）+ `DeviceInfo.toString()` 也要加新字段 + 1 个新测试 + 2 个测试扩充
- App：2 个文件修改 + 2 个测试扩充
- CLI：0 代码改动（取决于 implementer 在 Task 1 确认 CLI 是否走 toString；若不走则要在 CLI 里加 1 行字段渲染）
- 不引入新依赖
- 不动 Android manifest、构建配置

总代码增量 ~150 行 + ~30 行测试补充。
