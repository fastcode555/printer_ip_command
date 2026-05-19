# printer_ip_command

只用一个 IP,**并行 7 路通道**探测网络打印机的协议族、厂商、型号、状态,并打印 ESC/POS 测试小票。面向**外卖 / POS 热敏机**场景,默认配置走 HK Big5 编码。

```
✓ 7-channel parallel identification (1~2 秒出全报告)
✓ Safe-by-default + opt-in --deep   (不会误把垃圾打进纸里)
✓ Big5 / GBK / ASCII 编码可配         (HK / 大陆 / 英文)
✓ 一键脚本 bin/diagnose.sh           (自动绕 VPN + 探测 + 打印)
✓ 76 单元/集成测试,全绿
```

---

## Quick Start

```bash
# 一键诊断 + 打印一张测试小票(HK 默认 Big5)
./bin/diagnose.sh 192.168.1.123

# 给大陆 GBK 机
./bin/diagnose.sh 192.168.1.123 --encoding gbk

# 只看 7 通道报告,不出纸
./bin/diagnose.sh 192.168.1.123 --no-print

# 实验室深扫(PJL/ZPL/TSPL,可能让廉价机卡顿,生产环境别用)
./bin/diagnose.sh 192.168.1.123 --deep
```

如果 Mac 开了全段劫持 VPN(`utun*` 路由覆盖私网段),脚本会**自动**用 `sudo route` 加 host 路由绕过 — 当下需要输一次 sudo 密码。

---

## 7 通道一览

| # | 通道 | 端口 | 探针命令 | 拿什么 | 风险 |
|---|---|---|---|---|---|
| 1 | ESC/POS Probe | 9100/tcp | `DLE EOT 1` (0x10 04 01) | 协议确认 + 实时状态 | 🟢 安全(Epson 规范不进缓冲) |
| 2 | ESC/POS GS I | 9100/tcp | `GS I 65/66/67/68` | 厂商/型号/固件/序列号 | 🟢 仅在 ch1 确认 ESC/POS 后才发 |
| 3 | PJL | 9100/tcp | `\x1B%-12345X@PJL INFO ID...` | HP/办公机型号 | 🟠 **侵入** — 廉价机可能死机,默认 SKIPPED |
| 4 | IPP | 631/tcp | `Get-Printer-Attributes` | makeAndModel / 支持格式 | 🟢 独立端口 |
| 5 | SNMP v2c | 161/udp | `sysDescr` / Printer-MIB | 厂商 + 序列号 + 耗材 | 🟢 UDP 只读 |
| 6 | HTTP banner | 80/tcp | `GET /` → `Server:` + `<title>` | 厂商指纹兜底 | 🟢 独立端口 |
| 7 | mDNS browse | 5353/udp | `_ipp / _pdl-datastream / _printer ._tcp.local` | 自报型号 + 能力 TXT | 🟢 multicast 只听 |

**默认 SAFE 模式只跑 1/2/4/5/6/7**;3 (PJL) 被 gate 在 `--deep` 后,因为同事反馈 `ESC %-12345X` UEL 在部分廉价固件上会卡顿/死机。`--deep` 还会在 ch1 socket 里加发 ZPL `~HI`,这条命令**在 Epson 真机上会打印"~HI"字样**,只在实验室用。

---

## 仲裁链路(每个字段从哪条通道来)

```
vendor       ← GS I 66  →  HTTP vendorGuess
model        ← GS I 67  →  PJL  →  SNMP printerName  →  mDNS ty  →  IPP makeAndModel  →  HTTP title  →  SNMP sysDescr
firmware     ← GS I 65 (独占)
serial       ← GS I 68  →  SNMP printerSerial
makeAndModel ← IPP 原文
sysDescr/sysName       ← SNMP 独占
mdnsHostname/services  ← mDNS 独占
documentFormats        ← IPP + mDNS pdl 合并去重
escPosStatus           ← DLE EOT 1
```

CLI 在每个字段右侧标注 `← chN: 来源` 方便排查。

---

## 编码与中文

**打印机的中文字符 ROM 是硬件决定的**,软件不能切换。所以 `--encoding` 是**调用方必须根据目标市场配置**的参数,**绝不能**让程序自动检测(很可能"看起来像中文但全是错字",参见下方"已验证"事实)。

| `--encoding` | ESC/POS 设置 | 字节流 | 适用 |
|---|---|---|---|
| `big5`(默认) | `FS &` 进入 Chinese mode | Big5 双字节 | HK / TW 市场(Epson HK 变种 / 港台机) |
| `gbk` | `ESC t 0x15` 选码表 | GBK 双字节 | 大陆市场(国产热敏 / 大陆 Epson 变种) |
| `ascii` | (不发码表命令) | 仅 0x20~0x7E | 纯英文小票 |

**已验证事实**(实验室 EPSON TM-T88III,GBK ROM):
- 送 `gbk` 字节 → 简体中文正确打印 ✓
- 送 `big5` 字节 → 印出来仍是"看起来像汉字"的字符串,**但每个字都不对**(printer 用 GBK 表查每对 Big5 字节,结果是不相关的简体字)

**这是一个隐蔽的产品风险**:Big5 字节进 GBK 机器**不报错、不空白**,日均几百单的店家可能数周才发现错。所以接入 Flutter 时,encoding 应该是**按打印机/门店配置**的项,而不是全局默认。

---

## 7 通道实测分布参考

| 设备类型 | ch1 | ch2 | ch3 | ch4 | ch5 | ch6 | ch7 |
|---|---|---|---|---|---|---|---|
| Epson TM-T88III(2005,实验室) | ✓ | ✓ 全字段 | n/a | ✗ | ✗ | ✗ | ✗ |
| 现代 Epson POS(TM-T88V+) | ✓ | ✓ | n/a | ✓ | ✓ | ✓ | ✓ |
| Xprinter / 佳博 国产廉价 | ✓ | ✓ 部分字段 | n/a/✗ | ✗ | ✗ | ✓ HTTP | ✗ |
| HP 办公多功能机 | ✗ | ✗ | ✓(需 --deep) | ✓ | ✓ | ✓ | ✓ |
| Zebra / TSC 标签机 | 协议=zpl/tspl | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |

**多通道并行的价值**:任何一台设备至少 2~3 条通道命中,合并后总能拿到 vendor + model + 状态。

---

## API 在 Flutter 中怎么用

```dart
import 'package:printer_ip_command/printer_ip_command.dart';

// 1. 探测 + 识别
final report = await PrinterIdentifier.identify(
  '192.168.1.123',
  deep: false,                                  // safe mode
  timeout: const Duration(seconds: 2),
);
final device = report.device;                   // DeviceInfo
print('vendor=${device.vendor} model=${device.model}');

// 2. 直接发字节(基于探测结果的协议路由)
if (device.protocol == Protocol.escPos) {
  final bytes = buildReceipt(
    title: '外卖订单 #1234',
    lines: ['菜品 A x 1', '菜品 B x 2', '合计 ¥45'],
    encoding: ReceiptEncoding.big5,             // HK 门店
  );
  final socket = await Socket.connect(device.host, 9100);
  socket.add(bytes); await socket.flush(); await socket.close();
}
```

每个通道的原始结果在 `report.escPosProbe / .gsIdentity / .pjl / .ipp / .snmp / .http / .mdns` 上,带 `status` (success/failed/skipped) 和 `elapsed` 字段方便上层做"哪条通道贡献了什么数据"的可视化。

---

## 项目结构

```
lib/
  printer_ip_command.dart       公开 API
  src/
    probe.dart                  ch1 — ESC/POS 探针
    escpos_status.dart          DLE EOT 1 状态字节解析
    escpos_identity.dart        ch2 — GS I 65-68 身份查询
    escpos_receipt.dart         buildReceipt + ReceiptEncoding (gbk/big5/ascii)
    protocol.dart               协议枚举 + detectProtocol
    pjl_probe.dart              ch3 — PJL UEL(deep 才开)
    ipp_probe.dart              ch4 — IPP Get-Printer-Attributes
    snmp.dart                   SNMP v2c BER 编解码
    snmp_probe.dart             ch5 — SNMP UDP 查询
    http_fingerprint.dart       ch6 — HTTP banner 厂商指纹
    mdns_probe.dart             ch7 — mDNS browse + TXT 解析
    identifier.dart             PrinterIdentifier 并行编排 + 仲裁
bin/
  diagnose.sh                   ⭐ 一键脚本(VPN 绕路 + 探测 + 打印)
  printer_probe.dart            Dart CLI
  fake_printer.dart             本地模拟打印机(demo / 集成测)
  force_print.dart              直发字节绕过协议识别
test/
  ... 13 个测试文件,76 个 case
```

---

## 测试

```bash
fvm dart test --concurrency=1   # 顺序跑稳定;并发跑 mDNS 偶 flaky
```

---

## 已知 / 后续

- **mDNS 在 macOS 上偶 flaky**:多个 isolate 同时抢 multicast 端口。生产环境单实例不受影响。
- **跨子网 + 全段 VPN**:开发机走 VPN 会让所有探测返回 0 字节假象。`bin/diagnose.sh` 自动检测并加 host 路由。详见提交者 memory:`test-printer-vpn-bypass`。
- **TM-T88III 风险**:它是 GBK ROM,测试时**必须** `--encoding gbk`;HK 真机才用 `big5` 默认。
- **未实装通道**:WS-Discovery (3702/udp)、SSDP UPnP (1900/udp)、SNMP Printer-MIB 耗材 walk、ZPL/TSPL 身份追问。需要时再加。

---

## License

Internal — do not redistribute.
