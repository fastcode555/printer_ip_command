import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/widgets/print_test_dialog.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  testWidgets('default selection is Big5, Send returns selected encoding',
      (tester) async {
    ReceiptEncoding? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showPrintTestDialog(ctx);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Default radio is Big5 — tapping Send returns it.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, ReceiptEncoding.big5);
  });

  testWidgets('selecting GBK then Send returns GBK', (tester) async {
    ReceiptEncoding? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showPrintTestDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GBK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, ReceiptEncoding.gbk);
  });

  testWidgets('Cancel returns null', (tester) async {
    ReceiptEncoding? result = ReceiptEncoding.ascii;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showPrintTestDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
