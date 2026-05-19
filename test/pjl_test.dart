import 'dart:io';

import 'package:printer_ip_command/src/pjl_probe.dart';
import 'package:test/test.dart';

void main() {
  group('parsePjlResponse', () {
    test('extracts ID from @PJL INFO ID block (quoted)', () {
      const raw = '%-12345X@PJL INFO ID\r\n'
          '"HP LaserJet 4000"\r\n'
          ''
          '%-12345X';
      expect(parsePjlResponse(raw).modelId, 'HP LaserJet 4000');
    });

    test('extracts ID without quotes', () {
      const raw = '@PJL INFO ID\r\nXP-T80A\r\n';
      expect(parsePjlResponse(raw).modelId, 'XP-T80A');
    });

    test('extracts STATUS DISPLAY + ONLINE', () {
      const raw = '@PJL INFO STATUS\r\n'
          'CODE=10001\r\n'
          'DISPLAY="READY"\r\n'
          'ONLINE=TRUE\r\n'
          '';
      final r = parsePjlResponse(raw);
      expect(r.statusDisplay, 'READY');
      expect(r.online, isTrue);
    });

    test('extracts PAGECOUNT', () {
      const raw = '@PJL INFO PAGECOUNT\r\nPAGECOUNT=12345\r\n';
      expect(parsePjlResponse(raw).pageCount, 12345);
    });

    test('returns empty fields when no recognizable sections', () {
      final r = parsePjlResponse('garbage no PJL here');
      expect(r.modelId, isNull);
      expect(r.pageCount, isNull);
      expect(r.online, isNull);
    });

    test('handles mixed full response with all sections', () {
      const raw = '%-12345X@PJL INFO ID\r\n'
          '"Xprinter XP-T80A"\r\n'
          ''
          '@PJL INFO STATUS\r\n'
          'CODE=10001\r\n'
          'DISPLAY="READY"\r\n'
          'ONLINE=TRUE\r\n'
          ''
          '@PJL INFO PAGECOUNT\r\n'
          'PAGECOUNT=42\r\n'
          ''
          '%-12345X';
      final r = parsePjlResponse(raw);
      expect(r.modelId, 'Xprinter XP-T80A');
      expect(r.statusDisplay, 'READY');
      expect(r.online, isTrue);
      expect(r.pageCount, 42);
    });
  });

  group('PjlProbe.query (integration)', () {
    late ServerSocket server;

    tearDown(() => server.close());

    test('returns PjlResult when server echos canned response', () async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) async {
        // Drain probe input
        socket.listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        const reply = '%-12345X@PJL INFO ID\r\n'
            '"Brother HL-L2360DW"\r\n'
            ''
            '%-12345X';
        socket.add(reply.codeUnits);
        await socket.flush();
        await socket.close();
      });

      final result = await PjlProbe.query(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(result, isNotNull);
      expect(result!.modelId, 'Brother HL-L2360DW');
    });

    test('returns null on connection refused', () async {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = tmp.port;
      await tmp.close();
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      final result = await PjlProbe.query(
        '127.0.0.1',
        port: closedPort,
        timeout: const Duration(milliseconds: 500),
      );
      expect(result, isNull);
    });
  });
}
