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
  });

  testWidgets('renders em-dash for null fields', (tester) async {
    const device = DeviceInfo(
      host: '10.0.0.1',
      protocol: Protocol.unknown,
    );

    await tester.pumpWidget(_wrap(const DeviceInfoPanel(device: device)));

    expect(find.text('—'), findsWidgets);
  });
}
