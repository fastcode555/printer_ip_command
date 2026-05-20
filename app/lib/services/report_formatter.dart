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
  _kv(buf, 'language', device.language);
  _kv(buf, 'Chinese ROM', _chineseRomText(classifyLanguage(device.language)));
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

String _chineseRomText(ChineseRom rom) {
  return switch (rom) {
    ChineseRom.traditional => '繁体 (Big5)',
    ChineseRom.simplified => '简体 (GBK)',
    ChineseRom.unknown => '未知',
  };
}
