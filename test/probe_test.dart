import 'dart:io';
import 'dart:typed_data';

import 'package:printer_ip_command/src/escpos_status.dart';
import 'package:printer_ip_command/src/probe.dart';
import 'package:printer_ip_command/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PrinterProbe.probe', () {
    late ServerSocket server;

    tearDown(() async {
      await server.close();
    });

    test('detects ESC/POS when server replies with valid DLE EOT 1 byte', () async {
      server = await _fakeServer((socket) async {
        await socket.first; // wait for first packet (the probe command)
        socket.add([0x16]);
        await socket.flush();
        await socket.close();
      });

      final result = await PrinterProbe.probe(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(result.protocol, Protocol.escPos);
      expect(result.status, isA<EscPosStatus>());
      expect((result.status as EscPosStatus).online, isTrue);
    });

    test('detects ZPL when server replies with ZEBRA banner', () async {
      server = await _fakeServer((socket) async {
        await socket.first;
        socket.add('ZEBRA TECHNOLOGIES,ZTC GK420d,V53.17.16Z\r\n'.codeUnits);
        await socket.flush();
        await socket.close();
      });

      final result = await PrinterProbe.probe(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(result.protocol, Protocol.zpl);
    });

    test('returns unknown protocol when server stays silent', () async {
      server = await _fakeServer((socket) async {
        await socket.first;
        // no reply; let probe time out reading
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await socket.close();
      });

      final result = await PrinterProbe.probe(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(milliseconds: 500),
      );

      expect(result.protocol, Protocol.unknown);
    });

    test('throws SocketException when host refuses connection', () async {
      // Use a port we know is not listening: bind then immediately close
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = tmp.port;
      await tmp.close();
      // assign `server` so tearDown doesn't fail
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      expect(
        () => PrinterProbe.probe(
          '127.0.0.1',
          port: closedPort,
          timeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}

Future<ServerSocket> _fakeServer(
  Future<void> Function(Socket socket) onConnection,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) async {
    try {
      await onConnection(socket);
    } catch (_) {
      await socket.close();
    }
  });
  return server;
}

// quiet unused-import lints in test runner harness
// ignore: unused_element
Uint8List _u(List<int> b) => Uint8List.fromList(b);
