import 'dart:io';
import 'dart:typed_data';

import 'package:printer_ip_command/src/snmp.dart';
import 'package:printer_ip_command/src/snmp_probe.dart';
import 'package:test/test.dart';

void main() {
  group('SnmpProbe.query (UDP integration)', () {
    late RawDatagramSocket server;
    late int serverPort;

    setUp(() async {
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = server.port;
    });

    tearDown(() async {
      server.close();
    });

    test('returns SnmpResult with sysDescr + sysName when server responds', () async {
      // Listen for incoming datagrams and reply with canned response.
      server.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = server.receive();
        if (dg == null) return;
        final reply = _buildCannedResponse({
          '1.3.6.1.2.1.1.1.0': 'EPSON TM-T88V firmware',
          '1.3.6.1.2.1.1.5.0': 'EPSONPRT01',
        });
        server.send(reply, dg.address, dg.port);
      });

      final result = await SnmpProbe.query(
        '127.0.0.1',
        port: serverPort,
        timeout: const Duration(seconds: 2),
      );

      expect(result, isNotNull);
      expect(result!.sysDescr, 'EPSON TM-T88V firmware');
      expect(result.sysName, 'EPSONPRT01');
    });

    test('returns null when server is silent (timeout)', () async {
      // server bound but ignores datagrams
      final result = await SnmpProbe.query(
        '127.0.0.1',
        port: serverPort,
        timeout: const Duration(milliseconds: 300),
      );
      expect(result, isNull);
    });

    test('extracts printer-MIB serial when present', () async {
      server.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = server.receive();
        if (dg == null) return;
        final reply = _buildCannedResponse({
          '1.3.6.1.2.1.1.1.0': 'Generic Printer',
          '1.3.6.1.2.1.43.5.1.1.17.1': 'SN-AB-001',
        });
        server.send(reply, dg.address, dg.port);
      });
      final result = await SnmpProbe.query('127.0.0.1', port: serverPort);
      expect(result?.printerSerial, 'SN-AB-001');
    });
  });
}

// ------- canned SNMP GetResponse builder -------

Uint8List _buildCannedResponse(Map<String, String> octetStrings) {
  final vbList = BytesBuilder();
  octetStrings.forEach((oid, value) {
    final oidBytes = encodeOid(oid);
    final inner = <int>[
      0x06, oidBytes.length, ...oidBytes,
      0x04, value.length, ...value.codeUnits,
    ];
    vbList.add(_tlv(0x30, inner));
  });
  final vbListTlv = _tlv(0x30, vbList.toBytes());

  final pdu = <int>[
    0x02, 0x01, 0x01,
    0x02, 0x01, 0x00,
    0x02, 0x01, 0x00,
    ...vbListTlv,
  ];
  final pduTlv = _tlv(0xA2, pdu);

  final msg = <int>[
    0x02, 0x01, 0x01,
    0x04, 0x06, ...'public'.codeUnits,
    ...pduTlv,
  ];
  return Uint8List.fromList(_tlv(0x30, msg));
}

List<int> _tlv(int tag, List<int> content) {
  final out = <int>[tag];
  final n = content.length;
  if (n < 128) {
    out.add(n);
  } else if (n < 256) {
    out.addAll([0x81, n]);
  } else {
    out.addAll([0x82, (n >> 8) & 0xFF, n & 0xFF]);
  }
  out.addAll(content);
  return out;
}
