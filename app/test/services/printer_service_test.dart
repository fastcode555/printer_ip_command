import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_app/services/printer_service.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  group('PrinterService.printTest', () {
    test('sends ESC @ init bytes to listening socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final receivedCompleter = Completer<List<int>>();
      server.listen((socket) {
        final buf = <int>[];
        socket.listen(
          buf.addAll,
          onDone: () {
            if (!receivedCompleter.isCompleted) receivedCompleter.complete(buf);
          },
        );
      });

      final service = PrinterService();
      final n = await service.printTest(
        server.address.address,
        ReceiptEncoding.ascii,
        port: server.port,
      );

      expect(n, greaterThan(0));
      final received = await receivedCompleter.future
          .timeout(const Duration(seconds: 3));
      // First two bytes of buildReceipt output are ESC @ (init).
      expect(received[0], 0x1B);
      expect(received[1], 0x40);

      await server.close();
    });

    test('wraps connection refusal as PrintTestException', () async {
      // Bind then immediately close to obtain a port that's guaranteed closed.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();

      final service = PrinterService();
      expect(
        () => service.printTest(
          InternetAddress.loopbackIPv4.address,
          ReceiptEncoding.ascii,
          port: closedPort,
          connectTimeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<PrintTestException>()),
      );
    });
  });
}
