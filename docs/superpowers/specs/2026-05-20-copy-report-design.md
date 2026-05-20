# 复制完整探测报告按钮 — 设计

**日期：** 2026-05-20
**状态：** 已批准（待 spec review）

## 目标

在 Flutter app 的 `DiagnosePage` 上加一个"复制完整报告"按钮，把当前 `IdentifyReport`（DeviceInfo 摘要 + 7 个通道结果）一键复制到系统剪贴板，方便用户粘到 IM / 邮件 / bug ticket 里。

仅在 identify 已完成并产生结果时显示按钮（idle / loading 状态下不显示）。

## 架构

加 1 个新文件、改 2 个文件。文本格式化是纯函数，独立于 UI。Widget 边界不动 —— `DeviceInfoPanel` 仍然只关心渲染 `DeviceInfo`，通过可选 `onCopy` 回调向外暴露"复制"动作，由 `DiagnosePage` 注入实际逻辑（拿全量 `IdentifyReport` + 写剪贴板 + 弹 snackbar）。

```
app/lib/
├── services/
│   ├── printer_service.dart           (unchanged)
│   └── report_formatter.dart        ← NEW: formatReportAsText(IdentifyReport)
├── widgets/
│   └── device_info_panel.dart       ← 加可选 onCopy 参数 + 右上角 IconButton
└── pages/
    └── diagnose_page.dart           ← 给 DeviceInfoPanel 传 onCopy 回调
```

## 组件契约

### `report_formatter.dart`（新）

```dart
/// Render the full identify report as plain text (CLI-style multi-line).
/// Pure function, no I/O, no UI dependencies.
String formatReportAsText(IdentifyReport report);
```

输出格式（示例）：
```
host            : 192.168.225.78
protocol        : escPos
vendor          : EPSON
model           : TM-T88III
firmware        : 8.00 ESC/POS
serial          : E2QG064874
mDNS hostname   : —
formats         : —

ch1 ESC/POS probe    [✓]   1121 ms   protocol: escPos
ch2 GS I             [✓]    831 ms   EPSON / TM-T88III
ch3 PJL              [-]      0 ms   only runs with --deep
ch4 IPP              [✗]   1024 ms   no IPP response (port closed or path mismatch)
ch5 SNMP             [✗]   2006 ms   no SNMP response (agent disabled or community mismatch)
ch6 HTTP             [✗]    227 ms   no HTTP banner (port closed or non-HTTP)
ch7 mDNS             [✗]   2029 ms   no mDNS service matching this IP (device not advertising)
```

规则：
- 顶部 8 行：`host` / `protocol` / `vendor` / `model` / `firmware` / `serial` / `mDNS hostname` / `formats`。固定顺序、左列 16 字符宽对齐。
- 空字段（`null` 或空列表）渲染为 `—`（em-dash）。
- `formats` 把 `device.documentFormats` 用 `, ` 连起来；空列表 → `—`。
- 空一行分隔头部和通道列表。
- 7 行通道：`ch1 ESC/POS probe` / `ch2 GS I` / `ch3 PJL` / `ch4 IPP` / `ch5 SNMP` / `ch6 HTTP` / `ch7 mDNS`。和 UI 上 ChannelCard 的 label 完全一致。
- 状态符号：`✓` 成功 / `✗` 失败 / `-` 跳过。包在 `[ ]` 里。
- elapsed 渲染为：数字部分右对齐 4 字符宽，后接空格和 `ms`（例：`1121 ms` / ` 831 ms` / `   0 ms`）。
- summary 字符串和 ChannelCard 上显示的完全一致。每个通道的成功路径字段不同（ch1 protocol / ch2 manufacturer+model / ch3 modelId / ch4 makeAndModel / ch5 sysDescr / ch6 title / ch7 hostname），失败走 `outcome.error`，跳过走 `outcome.error`。在 formatter 里硬编码 7 个 case 直接复制 `diagnose_page.dart:_buildResult` 中的逻辑，不抽共享 helper —— 只有 2 个 consumer，提前抽象不划算；未来加第三个再 refactor。

### `DeviceInfoPanel` 修改

签名加可选参数：
```dart
class DeviceInfoPanel extends StatelessWidget {
  final DeviceInfo device;
  final VoidCallback? onCopy;
  const DeviceInfoPanel({super.key, required this.device, this.onCopy});
}
```

渲染规则：
- `onCopy == null` → 标题行仍然只显示灰色 "Device" 字样。不渲染复制图标。
- `onCopy != null` → 标题行变成 `Row(spaceBetween)`，左边 "Device"，右边 `IconButton(icon: Icon(Icons.copy_outlined, size: 20), tooltip: '复制完整报告', onPressed: onCopy)`。

为什么 `DeviceInfoPanel` 不直接拿 `IdentifyReport`：它的语义是"渲染 DeviceInfo 摘要"。如果让它知道 `IdentifyReport`，就把 UI 组件和"全量报告"概念耦合了。`onCopy` 回调让责任反向：panel 只负责"用户表达了复制意图"，怎么序列化、复制什么、反馈什么由调用方决定。这样 panel 既能在"复制全量报告"场景用，也能在未来"只复制 DeviceInfo"或"不允许复制"场景复用。

### `DiagnosePage` 修改

`_buildResult` 里的 `DeviceInfoPanel(device: report.device)` 改成：
```dart
DeviceInfoPanel(
  device: report.device,
  onCopy: () => _copyReport(report),
)
```

新增方法：
```dart
Future<void> _copyReport(IdentifyReport report) async {
  await Clipboard.setData(ClipboardData(text: formatReportAsText(report)));
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: Colors.green.shade700,
    content: const Text('已复制完整报告'),
    duration: const Duration(seconds: 2),
  ));
}
```

- 用 `Clipboard.setData`（`package:flutter/services.dart`，无需新依赖）。
- 写剪贴板是 async 但不会失败（Android/Windows 平台都稳）。不加 try/catch；若真失败，框架会抛 PlatformException，让它冒泡变成红 snackbar 的话需要 wrap —— 但平台原生剪贴板 API 实际上不会拒绝写入。保持简单。
- `mounted` check：写剪贴板有 await，理论上能被打断。守一下没坏处。

## 错误处理

- `Clipboard.setData` 平台层不会抛错，不加 try/catch。
- 若用户在 identify 完成前点了复制 —— 不可能：按钮只在 `_pending` 已有 data 时才渲染（通过 `onCopy != null` 控制）。在 idle / loading 状态下 `DeviceInfoPanel` 根本不出现。

## 测试

### 新测试

**`app/test/services/report_formatter_test.dart`**（纯函数单测）

一个测试用例。喂一个 canned `IdentifyReport`（手工构造 7 个 `ChannelOutcome` 覆盖三种 status），断言输出文本包含：
- `host            : 192.168.225.78`
- `vendor          : EPSON`
- `protocol        : escPos`
- `ch1 ESC/POS probe`（带 `[✓]`）
- `ch3 PJL`（带 `[-]`）
- `ch4 IPP`（带 `[✗]`）
- 空字段渲染为 `—`

不验证字节级一致，只验证关键 token 都在。这样格式微调（多/少一个空格）不会让测试 brittle。

**`DeviceInfoPanel` widget test 加 1 case**

```dart
testWidgets('onCopy non-null → copy icon renders and triggers callback', ...);
```
- 用 `_FakeService`-style 构造，但这里更简单：直接 pump `DeviceInfoPanel(device: ..., onCopy: () { tapped = true; })`。
- 查找 `find.byIcon(Icons.copy_outlined)` → findsOneWidget。
- `tester.tap(...)` → `expect(tapped, true)`。

`onCopy: null` 的回归测试：原本的两个 case 不传 `onCopy`，加一行 `expect(find.byIcon(Icons.copy_outlined), findsNothing)` 确保旧路径没意外渲染图标。

**`DiagnosePage` widget test 加 1 case**

```dart
testWidgets('tapping copy icon writes formatted report to clipboard', ...);
```

用 `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler` 拦截 `SystemChannels.platform` 上的 `Clipboard.setData`：
- 触发 identify（同已有的成功 case）。
- 点 `find.byIcon(Icons.copy_outlined)`。
- 断言 mock handler 收到 `setData` 调用，且 args['text'] 以 `host` 开头并包含 `ch1 ESC/POS probe`。
- 断言 snackbar 出现：`find.text('已复制完整报告')` findsOneWidget。

### 不动的测试

现有 14 个测试不动。新增 3 个，合计 17 个。

## Non-goals

- 不加"按通道单独复制"
- 不加历史 / 多份导出
- 不加 i18n —— 报告内容用英文（与 CLI 对齐、跨团队可读），snackbar 文案用中文（终端用户）
- 不加复制为 Markdown / JSON（仅纯文本，已和用户确认）
- 不加 share intent（Android `share` 是另一个特性，不在本次范围）

## 影响范围

- 增量代码 ~120 行（formatter ~50 + panel diff ~10 + page diff ~15 + 3 个测试 ~45）。
- 不引入新依赖。`Clipboard` 已经在 `package:flutter/services.dart`。
- 不动现有库 (`lib/`)、构建配置、Android manifest。
- CLI 行为不动。
