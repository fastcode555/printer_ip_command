import 'dart:io';

import 'package:printer_ip_command/src/http_fingerprint.dart';
import 'package:test/test.dart';

void main() {
  group('extractFingerprint (pure)', () {
    test('extracts <title> case-insensitively', () {
      const html = '<html><head><TITLE>XP-T80A Web Configurator</TITLE></head>';
      final fp = extractFingerprint(serverHeader: null, body: html);
      expect(fp.title, 'XP-T80A Web Configurator');
    });

    test('vendor guess "EPSON" from body text', () {
      const html = '<html>Welcome to EPSON TM-T88V Setup</html>';
      final fp = extractFingerprint(serverHeader: null, body: html);
      expect(fp.vendorGuess, 'EPSON');
    });

    test('vendor guess from Server header overrides body', () {
      const html = '<html>Generic page</html>';
      final fp = extractFingerprint(
        serverHeader: 'EpsonNet WebConfig 1.0',
        body: html,
      );
      expect(fp.vendorGuess, 'EPSON');
      expect(fp.serverHeader, 'EpsonNet WebConfig 1.0');
    });

    test('returns null fields when nothing recognizable', () {
      final fp = extractFingerprint(serverHeader: null, body: '<html></html>');
      expect(fp.title, isNull);
      expect(fp.vendorGuess, isNull);
    });

    test('recognizes common vendors: HP, Brother, Canon, Xprinter', () {
      expect(extractFingerprint(serverHeader: null, body: 'HP LaserJet')
          .vendorGuess, 'HP');
      expect(extractFingerprint(serverHeader: null, body: 'Brother Embedded')
          .vendorGuess, 'Brother');
      expect(extractFingerprint(serverHeader: null, body: 'Canon iR Series')
          .vendorGuess, 'Canon');
      expect(extractFingerprint(serverHeader: null, body: 'Xprinter cloud panel')
          .vendorGuess, 'Xprinter');
    });
  });

  group('HttpFingerprintProbe.query (integration)', () {
    late HttpServer server;

    tearDown(() => server.close(force: true));

    test('extracts title + server header from canned response', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..headers.set('Server', 'EpsonNet WebConfig')
          ..headers.contentType = ContentType.html
          ..write('<html><head><title>Epson TM-T88V Setup</title></head></html>');
        await req.response.close();
      });

      final fp = await HttpFingerprintProbe.query(
        '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );

      expect(fp, isNotNull);
      expect(fp!.serverHeader, contains('EpsonNet'));
      expect(fp.title, 'Epson TM-T88V Setup');
      expect(fp.vendorGuess, 'EPSON');
    });

    test('returns null on connection refused', () async {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = tmp.port;
      await tmp.close();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final fp = await HttpFingerprintProbe.query(
        '127.0.0.1',
        port: port,
        timeout: const Duration(milliseconds: 500),
      );
      expect(fp, isNull);
    });
  });
}
