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
