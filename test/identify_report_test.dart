import 'dart:io';
import 'dart:typed_data';

import 'package:printer_ip_command/src/identifier.dart';
import 'package:test/test.dart';

void main() {
  group('PrinterIdentifier.identify → IdentifyReport', () {
    late ServerSocket tcpServer;
    late HttpServer ippServer;

    tearDown(() async {
      await tcpServer.close();
      await ippServer.close(force: true);
    });

    test('successful 9100 probe + IPP yields per-channel SUCCESS with elapsed > 0', () async {
      tcpServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var conn = 0;
      tcpServer.listen((socket) async {
        conn++;
        if (conn == 1) {
          // probe connection: reply with ESC/POS status byte
          socket.add([0x16]);
          await socket.flush();
          await socket.close();
        } else {
          // GS I connection: reply in GS I 65/66/67/68 order
          socket.listen((_) {});
          await Future<void>.delayed(const Duration(milliseconds: 20));
          socket.add('FW1'.codeUnits + [0x00]);       // 65 firmware
          socket.add('Xprinter'.codeUnits + [0x00]);  // 66 manufacturer
          socket.add('XP-T80A'.codeUnits + [0x00]);   // 67 model
          socket.add('SN1'.codeUnits + [0x00]);       // 68 serial
          await socket.flush();
          await socket.close();
        }
      });
      ippServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ippServer.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'ipp')
          ..add(_ippSample());
        await req.response.close();
      });

      final report = await PrinterIdentifier.identify(
        '127.0.0.1',
        rawPort: tcpServer.port,
        ippPort: ippServer.port,
        timeout: const Duration(seconds: 2),
      );

      expect(report.host, '127.0.0.1');
      expect(report.escPosProbe.status, ChannelStatus.success);
      expect(report.escPosProbe.elapsed.inMicroseconds, greaterThan(0));

      expect(report.ipp.status, ChannelStatus.success);
      expect(report.ipp.value?.makeAndModel, 'Epson TM-T88V');

      expect(report.gsIdentity.status, ChannelStatus.success);
      expect(report.gsIdentity.value?.manufacturer, 'Xprinter');

      // Final aggregated model is also in the report.
      expect(report.device.protocol.name, 'escPos');
      expect(report.device.vendor, 'Xprinter');
    });

    test('IPP port closed → ipp channel FAILED, others still succeed', () async {
      tcpServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      tcpServer.listen((socket) async {
        socket.add([0x16]);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await socket.close();
      });
      // Bind+close a port to get a known-closed one.
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = tmp.port;
      await tmp.close();
      // We still need ippServer for tearDown; use any new port.
      ippServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final report = await PrinterIdentifier.identify(
        '127.0.0.1',
        rawPort: tcpServer.port,
        ippPort: closedPort,
        timeout: const Duration(milliseconds: 500),
      );

      expect(report.escPosProbe.status, ChannelStatus.success);
      expect(report.ipp.status, ChannelStatus.failed);
      expect(report.ipp.value, isNull);
      expect(report.ipp.error, isNotEmpty);
    });

    test('GS I channel skipped when protocol is not ESC/POS', () async {
      tcpServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      tcpServer.listen((socket) async {
        // Reply with non-ESC/POS payload (ZEBRA banner)
        socket.add('ZEBRA TECHNOLOGIES\r\n'.codeUnits);
        await socket.flush();
        await socket.close();
      });
      ippServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final report = await PrinterIdentifier.identify(
        '127.0.0.1',
        rawPort: tcpServer.port,
        ippPort: ippServer.port,
        timeout: const Duration(milliseconds: 800),
      );

      expect(report.escPosProbe.status, ChannelStatus.success);
      expect(report.gsIdentity.status, ChannelStatus.skipped);
      expect(report.device.protocol.name, 'zpl');
    });
  });
}

Uint8List _ippSample() {
  final b = BytesBuilder();
  b.add([0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]);
  b.addByte(0x01);
  _attr(b, 0x47, 'attributes-charset', 'utf-8');
  _attr(b, 0x48, 'attributes-natural-language', 'en');
  b.addByte(0x04);
  _attr(b, 0x41, 'printer-make-and-model', 'Epson TM-T88V');
  b.addByte(0x03);
  return b.toBytes();
}

void _attr(BytesBuilder b, int tag, String name, String value) {
  b.addByte(tag);
  b.add([(name.length >> 8) & 0xFF, name.length & 0xFF]);
  b.add(name.codeUnits);
  b.add([(value.length >> 8) & 0xFF, value.length & 0xFF]);
  b.add(value.codeUnits);
}
