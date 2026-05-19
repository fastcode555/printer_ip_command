import 'dart:io';

import 'package:printer_ip_command/printer_ip_command.dart';

const _usage = '''
Usage: dart run bin/printer_probe.dart <ip> [opts]

  --raw-port   Raw TCP port    (default 9100)
  --ipp-port   IPP port        (default 631)
  --snmp-port  SNMP UDP port   (default 161)
  --http-port  HTTP port       (default 80)
  --community  SNMP community  (default "public")
  --print      Send a test receipt if protocol == escPos
  --encoding   Receipt text encoding for --print: big5 | gbk | ascii
               (default big5 — HK / Traditional Chinese market)
  --deep       Enable invasive probes (PJL, ZPL ~HI, TSPL ~!T).
               WARNING: may print garbage or wedge some cheap thermal
               firmwares. Use in lab/diagnostic only — NOT in production.
''';

Future<int> main(List<String> argv) async {
  if (argv.isEmpty || argv.first.startsWith('-')) {
    stderr.writeln(_usage);
    return 64;
  }

  final host = argv.first;
  var rawPort = 9100;
  var ippPort = 631;
  var snmpPort = 161;
  var httpPort = 80;
  var community = 'public';
  var doPrint = false;
  var deep = false;
  var encoding = ReceiptEncoding.big5;

  for (var i = 1; i < argv.length; i++) {
    final a = argv[i];
    if (a == '--raw-port' && i + 1 < argv.length) {
      rawPort = int.parse(argv[++i]);
    } else if (a == '--ipp-port' && i + 1 < argv.length) {
      ippPort = int.parse(argv[++i]);
    } else if (a == '--snmp-port' && i + 1 < argv.length) {
      snmpPort = int.parse(argv[++i]);
    } else if (a == '--http-port' && i + 1 < argv.length) {
      httpPort = int.parse(argv[++i]);
    } else if (a == '--community' && i + 1 < argv.length) {
      community = argv[++i];
    } else if (a == '--print') {
      doPrint = true;
    } else if (a == '--deep') {
      deep = true;
    } else if (a == '--encoding' && i + 1 < argv.length) {
      final v = argv[++i].toLowerCase();
      encoding = switch (v) {
        'big5' => ReceiptEncoding.big5,
        'gbk' => ReceiptEncoding.gbk,
        'ascii' => ReceiptEncoding.ascii,
        _ => throw FormatException('--encoding must be one of big5|gbk|ascii (got "$v")'),
      };
    } else {
      stderr.writeln('Unknown arg: $a\n$_usage');
      return 64;
    }
  }

  print('========================================');
  print('Identifying $host');
  print('  raw:$rawPort  ipp:$ippPort  snmp:$snmpPort  http:$httpPort');
  if (deep) {
    print('  mode: ⚠ DEEP (invasive probes enabled — may print garbage)');
  } else {
    print('  mode: SAFE (PJL / ZPL / TSPL skipped)');
  }
  print('========================================\n');

  final report = await PrinterIdentifier.identify(
    host,
    rawPort: rawPort,
    ippPort: ippPort,
    snmpPort: snmpPort,
    httpPort: httpPort,
    snmpCommunity: community,
    deep: deep,
  );

  _printChannel1EscPos(report, rawPort, deep);
  _printChannel2GsIdentity(report, rawPort);
  _printChannel3Pjl(report, rawPort);
  _printChannel4Ipp(report, ippPort);
  _printChannel5Snmp(report, snmpPort, community);
  _printChannel6Http(report, httpPort);
  _printChannel7Mdns(report);
  _printAggregated(report);

  if (doPrint) {
    if (report.device.protocol != Protocol.escPos) {
      stderr.writeln('\n--print requires ESC/POS (got ${report.device.protocol.name})');
      return 3;
    }
    await _sendTestReceipt(host, rawPort, report.device, encoding);
  }
  // Force exit: MDnsClient / HttpClient occasionally leave lingering sockets
  // that keep the event loop alive past main(). Safe here because we have no
  // pending writes once all reports + receipts have flushed.
  exit(0);
}

void _printChannel1EscPos(IdentifyReport report, int rawPort, bool deep) {
  final ch = report.escPosProbe;
  print('[1/7] ESC/POS / Raw protocol probe   (TCP $rawPort)');
  if (deep) {
    print('      Commands: DLE EOT 1 (0x10 04 01)  +  ZPL ~HI  [DEEP MODE]');
  } else {
    print('      Commands: DLE EOT 1 (0x10 04 01) only  (safe — no print buffer side-effects)');
  }
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final pr = ch.value!;
    print('      protocol         : ${pr.protocol.name}');
    print('      raw bytes (${pr.raw.length})   : ${_hex(pr.raw)}');
    if (pr.status != null) {
      print('      escPos status    : ${pr.status}');
    }
    final ascii = _safeAscii(pr.raw);
    if (ascii.isNotEmpty) print('      raw ascii        : $ascii');
  }
  print('');
}

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

void _printChannel3Pjl(IdentifyReport report, int rawPort) {
  final ch = report.pjl;
  print('[3/7] PJL Universal Exit Language     (TCP $rawPort)');
  print('      Commands: @PJL INFO ID + STATUS + PAGECOUNT');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final p = ch.value!;
    print('      modelId          : ${p.modelId ?? "(none)"}');
    print('      statusDisplay    : ${p.statusDisplay ?? "(none)"}');
    print('      online           : ${p.online?.toString() ?? "(none)"}');
    print('      pageCount        : ${p.pageCount?.toString() ?? "(none)"}');
  }
  print('');
}

void _printChannel4Ipp(IdentifyReport report, int ippPort) {
  final ch = report.ipp;
  print('[4/7] IPP Get-Printer-Attributes      (TCP $ippPort)');
  print('      HTTP POST /ipp/print  Content-Type: application/ipp');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final ipp = ch.value!;
    print('      ipp statusCode   : 0x${ipp.statusCode.toRadixString(16).padLeft(4, "0")}');
    print('      makeAndModel     : ${ipp.makeAndModel ?? "(none)"}');
    print('      printer-state    : ${_ippStateLabel(ipp.state)}');
    print('      documentFormats  : ${ipp.documentFormats.isEmpty ? "(none)" : ipp.documentFormats.join(", ")}');
  }
  print('');
}

void _printChannel5Snmp(IdentifyReport report, int snmpPort, String community) {
  final ch = report.snmp;
  print('[5/7] SNMP v2c GET                    (UDP $snmpPort, community="$community")');
  print('      OIDs: sysDescr / sysName / prtGeneralPrinterName / prtGeneralSerialNumber');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final s = ch.value!;
    print('      sysDescr         : ${s.sysDescr ?? "(none)"}');
    print('      sysName          : ${s.sysName ?? "(none)"}');
    print('      printerName      : ${s.printerName ?? "(none)"}');
    print('      printerSerial    : ${s.printerSerial ?? "(none)"}');
  }
  print('');
}

void _printChannel6Http(IdentifyReport report, int httpPort) {
  final ch = report.http;
  print('[6/7] HTTP banner / web admin         (TCP $httpPort)');
  print('      GET / → parse Server header + <title> + vendor markers');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final h = ch.value!;
    print('      httpStatusCode   : ${h.statusCode}');
    print('      serverHeader     : ${h.serverHeader ?? "(none)"}');
    print('      title            : ${h.title ?? "(none)"}');
    print('      vendorGuess      : ${h.vendorGuess ?? "(none)"}');
  }
  print('');
}

void _printChannel7Mdns(IdentifyReport report) {
  final ch = report.mdns;
  print('[7/7] mDNS service discovery          (UDP 5353 multicast)');
  print('      Browse: _ipp / _ipps / _pdl-datastream / _printer  ._tcp.local');
  _printOutcomeHeader(ch);
  if (ch.ok) {
    final m = ch.value!;
    print('      services         : ${m.services.join(", ")}');
    print('      hostname         : ${m.hostname ?? "(none)"}');
    print('      modelGuess (ty)  : ${m.modelGuess ?? "(none)"}');
    print('      adminUrl         : ${m.adminUrl ?? "(none)"}');
    print('      supportedFormats : ${m.supportedFormats.isEmpty ? "(none)" : m.supportedFormats.join(", ")}');
    if (m.txt.isNotEmpty) {
      print('      raw TXT keys     : ${m.txt.keys.join(", ")}');
    }
  }
  print('');
}

void _printAggregated(IdentifyReport report) {
  final d = report.device;
  print('========================================');
  print('Aggregated DeviceInfo');
  print('========================================');
  _row('host',          d.host,          source: 'input');
  _row('protocol',      d.protocol.name, source: report.escPosProbe.ok ? 'ch1: ESC/POS probe' : '(unknown)');
  _row('vendor',        d.vendor,        source: _vendorSource(report, d));
  _row('model',         d.model,         source: _modelSource(report, d));
  _row('firmware',      d.firmware,      source: report.gsIdentity.ok && d.firmware != null ? 'ch2: GS I 65' : '(none)');
  _row('serial',        d.serial,        source: _serialSource(report, d));
  _row('makeAndModel',  d.makeAndModel,  source: report.ipp.ok ? 'ch4: IPP' : '(none)');
  _row('sysDescr',      d.sysDescr,      source: report.snmp.ok && d.sysDescr != null ? 'ch5: SNMP sysDescr' : '(none)');
  _row('sysName',       d.sysName,       source: report.snmp.ok && d.sysName != null ? 'ch5: SNMP sysName' : '(none)');
  _row('mdnsHostname',  d.mdnsHostname,  source: report.mdns.ok && d.mdnsHostname != null ? 'ch7: mDNS SRV target' : '(none)');
  _row('mdnsServices',  d.mdnsServices.isEmpty ? null : d.mdnsServices.join(', '),
       source: report.mdns.ok ? 'ch7: mDNS browse' : '(none)');
  _row('escPosStatus',  d.escPosStatus,  source: report.escPosProbe.ok ? 'ch1: DLE EOT 1' : '(none)');
  _row('ippState',      _ippStateLabel(d.ippState), source: report.ipp.ok ? 'ch4: IPP' : '(none)');
  _row('documentFormats', d.documentFormats.isEmpty ? null : d.documentFormats.join(', '),
       source: _formatsSource(report));
  print('');
}

String _formatsSource(IdentifyReport r) {
  final hasIpp = r.ipp.ok && (r.ipp.value?.documentFormats.isNotEmpty ?? false);
  final hasMdns = r.mdns.ok && (r.mdns.value?.supportedFormats.isNotEmpty ?? false);
  if (hasIpp && hasMdns) return 'ch4: IPP + ch7: mDNS';
  if (hasIpp) return 'ch4: IPP';
  if (hasMdns) return 'ch7: mDNS pdl';
  return '(none)';
}

String _vendorSource(IdentifyReport r, DeviceInfo d) {
  if (d.vendor == null) return '(none)';
  if (r.gsIdentity.ok && r.gsIdentity.value?.manufacturer != null) return 'ch2: GS I 66';
  if (r.http.ok && r.http.value?.vendorGuess != null) return 'ch6: HTTP vendor heuristic';
  return '(none)';
}

void _printOutcomeHeader(ChannelOutcome<dynamic> ch) {
  final ms = ch.elapsed.inMilliseconds;
  switch (ch.status) {
    case ChannelStatus.success:
      print('      status           : ✓ SUCCESS  ($ms ms)');
      break;
    case ChannelStatus.failed:
      print('      status           : ✗ FAILED   ($ms ms)  — ${ch.error}');
      break;
    case ChannelStatus.skipped:
      print('      status           : - SKIPPED  — ${ch.error}');
      break;
  }
}

String _modelSource(IdentifyReport r, DeviceInfo d) {
  if (d.model == null) return '(none)';
  if (r.gsIdentity.ok && r.gsIdentity.value?.model != null) return 'ch2: GS I 67';
  if (r.pjl.ok && r.pjl.value?.modelId != null) return 'ch3: PJL INFO ID';
  if (r.snmp.ok && r.snmp.value?.printerName != null) return 'ch5: SNMP prtGeneralPrinterName';
  if (r.mdns.ok && r.mdns.value?.modelGuess != null) return 'ch7: mDNS TXT ty';
  if (r.ipp.ok && r.ipp.value?.makeAndModel != null) return 'ch4: IPP makeAndModel';
  if (r.http.ok && r.http.value?.title != null) return 'ch6: HTTP <title>';
  if (r.snmp.ok && r.snmp.value?.sysDescr != null) return 'ch5: SNMP sysDescr (fallback)';
  return '(none)';
}

String _serialSource(IdentifyReport r, DeviceInfo d) {
  if (d.serial == null) return '(none)';
  if (r.gsIdentity.ok && r.gsIdentity.value?.serial != null) return 'ch2: GS I 68';
  if (r.snmp.ok && r.snmp.value?.printerSerial != null) return 'ch5: SNMP prtGeneralSerialNumber';
  return '(none)';
}

String _ippStateLabel(int? s) {
  if (s == null) return '(none)';
  return switch (s) {
    3 => '3 (idle)',
    4 => '4 (processing)',
    5 => '5 (stopped)',
    _ => '$s',
  };
}

void _row(String label, Object? value, {required String source}) {
  final v = value == null || value.toString().isEmpty ? '(none)' : value.toString();
  print('  ${label.padRight(16)}: ${v.padRight(32)}  ← $source');
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

String _safeAscii(List<int> b) {
  final sb = StringBuffer();
  for (final c in b) {
    if (c >= 0x20 && c <= 0x7E) {
      sb.writeCharCode(c);
    } else if (c == 0x0A || c == 0x0D || c == 0x09) {
      sb.write(' ');
    } else {
      return '';
    }
  }
  return sb.toString().trim();
}

Future<void> _sendTestReceipt(
  String host,
  int port,
  DeviceInfo info,
  ReceiptEncoding encoding,
) async {
  final (title, lines) = _receiptText(host, info, encoding);
  final bytes = buildReceipt(title: title, lines: lines, encoding: encoding);
  print('Sending ${bytes.length} bytes test receipt (encoding: ${encoding.name}) ...');
  final socket = await Socket.connect(host, port,
      timeout: const Duration(seconds: 3));
  try {
    socket.add(bytes);
    await socket.flush();
  } finally {
    await socket.close();
  }
  print('Done.');
}

(String, List<String>) _receiptText(
  String host,
  DeviceInfo info,
  ReceiptEncoding encoding,
) {
  final ts = DateTime.now().toIso8601String();
  switch (encoding) {
    case ReceiptEncoding.big5:
      return (
        '測試小票',
        [
          '--------------------------------',
          'IP       : $host',
          '協定     : ${info.protocol.name}',
          if (info.vendor != null) '廠商     : ${info.vendor}',
          if (info.model != null) '型號     : ${info.model}',
          if (info.firmware != null) '韌體     : ${info.firmware}',
          '時間     : $ts',
          '--------------------------------',
          '這是一張來自 printer_ip_command',
          '的繁體中文測試單 (Big5)。',
          '香港市場使用此編碼。',
        ],
      );
    case ReceiptEncoding.gbk:
      return (
        '测试小票',
        [
          '--------------------------------',
          'IP       : $host',
          '协议     : ${info.protocol.name}',
          if (info.vendor != null) '厂商     : ${info.vendor}',
          if (info.model != null) '型号     : ${info.model}',
          if (info.firmware != null) '固件     : ${info.firmware}',
          '时间     : $ts',
          '--------------------------------',
          '这是一张来自 printer_ip_command',
          '的简体中文测试单 (GBK)。',
        ],
      );
    case ReceiptEncoding.ascii:
      return (
        'Test Receipt',
        [
          '--------------------------------',
          'IP       : $host',
          'Protocol : ${info.protocol.name}',
          if (info.vendor != null) 'Vendor   : ${info.vendor}',
          if (info.model != null) 'Model    : ${info.model}',
          if (info.firmware != null) 'Firmware : ${info.firmware}',
          'Time     : $ts',
          '--------------------------------',
          'printer_ip_command test slip.',
        ],
      );
  }
}
