import 'dart:io';
import 'dart:typed_data';

import 'package:printer_ip_command/src/ipp_probe.dart';
import 'package:test/test.dart';

void main() {
  group('buildIppGetPrinterAttributesRequest', () {
    test('starts with IPP 1.1 version, op-id 0x000B, request-id 1', () {
      final body = buildIppGetPrinterAttributesRequest(
        printerUri: 'ipp://1.2.3.4:631/ipp/print',
        requestId: 1,
      );
      expect(body[0], 0x01);
      expect(body[1], 0x01);
      expect(body[2], 0x00);
      expect(body[3], 0x0B);
      expect(body.sublist(4, 8), [0x00, 0x00, 0x00, 0x01]);
    });

    test('ends with end-of-attributes-tag (0x03)', () {
      final body = buildIppGetPrinterAttributesRequest(
        printerUri: 'ipp://x/ipp/print',
        requestId: 1,
      );
      expect(body.last, 0x03);
    });

    test('contains operation-attributes-tag (0x01) and the printer-uri', () {
      final body = buildIppGetPrinterAttributesRequest(
        printerUri: 'ipp://1.2.3.4:631/ipp/print',
        requestId: 1,
      );
      expect(body.contains(0x01), isTrue);
      final s = String.fromCharCodes(body);
      expect(s.contains('printer-uri'), isTrue);
      expect(s.contains('ipp://1.2.3.4:631/ipp/print'), isTrue);
    });
  });

  group('parseIppResponse', () {
    test('extracts printer-make-and-model (textWithoutLanguage)', () {
      final bytes = _sampleResponse();
      final parsed = parseIppResponse(bytes);
      expect(parsed.makeAndModel, 'Epson TM-T88V');
    });

    test('extracts printer-state as int (3 = idle)', () {
      final parsed = parseIppResponse(_sampleResponse());
      expect(parsed.state, 3);
    });

    test('extracts multi-value document-format-supported', () {
      final parsed = parseIppResponse(_sampleResponse());
      expect(parsed.documentFormats,
          containsAll(['text/plain', 'application/octet-stream']));
    });

    test('parses status-code from header (0x0000 = successful-ok)', () {
      final parsed = parseIppResponse(_sampleResponse());
      expect(parsed.statusCode, 0x0000);
    });
  });

  group('IppProbe.query (integration with local HTTP server)', () {
    late HttpServer server;

    tearDown(() => server.close(force: true));

    test('returns parsed result when server replies with valid IPP body', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('application', 'ipp')
          ..add(_sampleResponse());
        await req.response.close();
      });

      final result = await IppProbe.query(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(result, isNotNull);
      expect(result!.makeAndModel, 'Epson TM-T88V');
    });

    test('returns null on connection refused', () async {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = tmp.port;
      await tmp.close();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final result = await IppProbe.query(
        '127.0.0.1',
        port: port,
        timeout: const Duration(milliseconds: 500),
      );
      expect(result, isNull);
    });
  });
}

Uint8List _sampleResponse() {
  final b = BytesBuilder();
  // header
  b.add([0x01, 0x01]); // version 1.1
  b.add([0x00, 0x00]); // status-code: successful-ok
  b.add([0x00, 0x00, 0x00, 0x01]); // request-id

  // operation-attributes-tag
  b.addByte(0x01);
  _attr(b, 0x47, 'attributes-charset', 'utf-8');
  _attr(b, 0x48, 'attributes-natural-language', 'en');

  // printer-attributes-tag
  b.addByte(0x04);
  _attr(b, 0x41, 'printer-make-and-model', 'Epson TM-T88V');
  _attrInt(b, 0x23, 'printer-state', 3);
  _attr(b, 0x49, 'document-format-supported', 'text/plain');
  _attr(b, 0x49, '', 'application/octet-stream'); // multi-value

  // end-of-attributes-tag
  b.addByte(0x03);
  return b.toBytes();
}

void _attr(BytesBuilder b, int valueTag, String name, String value) {
  b.addByte(valueTag);
  b.add(_u16(name.length));
  b.add(name.codeUnits);
  b.add(_u16(value.length));
  b.add(value.codeUnits);
}

void _attrInt(BytesBuilder b, int valueTag, String name, int value) {
  b.addByte(valueTag);
  b.add(_u16(name.length));
  b.add(name.codeUnits);
  b.add(_u16(4));
  b.add(_u32(value));
}

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];
