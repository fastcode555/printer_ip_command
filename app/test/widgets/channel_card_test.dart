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
