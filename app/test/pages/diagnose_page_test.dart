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
    await tester.pump(); // rebuild so button becomes enabled
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
    await tester.pump(); // rebuild so button becomes enabled
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();
    expect(find.text('Send test receipt'), findsOneWidget);

    final notEscPos = _FakeService(_report(
      protocol: Protocol.unknown,
      probeStatus: ChannelStatus.failed,
    ));
    await tester.pumpWidget(MaterialApp(home: DiagnosePage(service: notEscPos)));
    await tester.enterText(find.byType(TextField), '10.0.0.1');
    await tester.pump(); // rebuild so button becomes enabled
    await tester.tap(find.widgetWithText(ElevatedButton, 'Identify'));
    await tester.pumpAndSettle();
    expect(find.text('Send test receipt'), findsNothing);
  });
}
