import 'dart:typed_data';

import 'package:printer_ip_command/src/snmp.dart';
import 'package:test/test.dart';

void main() {
  group('encodeOid', () {
    test('1.3.6.1.2.1.1.1.0 (sysDescr) → 8 bytes per BER', () {
      final encoded = encodeOid('1.3.6.1.2.1.1.1.0');
      expect(encoded, [0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00]);
    });

    test('arc >= 128 uses base-128 with continuation bits', () {
      // 1.2.840 — arc 840 = 0x348 → 0x86 0x48
      final encoded = encodeOid('1.2.840');
      expect(encoded, [0x2A, 0x86, 0x48]);
    });

    test('round-trip with decodeOid', () {
      const oid = '1.3.6.1.2.1.43.5.1.1.17.1';
      expect(decodeOid(encodeOid(oid)), oid);
    });
  });

  group('buildGetRequest', () {
    test('starts with SEQUENCE tag 0x30', () {
      final req = buildGetRequest(
        community: 'public',
        requestId: 1,
        oids: const ['1.3.6.1.2.1.1.1.0'],
      );
      expect(req[0], 0x30);
    });

    test('contains community string as OCTET STRING', () {
      final req = buildGetRequest(
        community: 'public',
        requestId: 1,
        oids: const ['1.3.6.1.2.1.1.1.0'],
      );
      // Find OCTET STRING (0x04) + length 6 + "public"
      final s = String.fromCharCodes(req);
      expect(s.contains('public'), isTrue);
    });

    test('version field is 1 (SNMPv2c)', () {
      final req = buildGetRequest(
        community: 'public',
        requestId: 1,
        oids: const ['1.3.6.1.2.1.1.1.0'],
      );
      // After 0x30 LL, INTEGER 0x02 0x01 0x01 (version=1)
      expect(req.sublist(2, 5), [0x02, 0x01, 0x01]);
    });
  });

  group('parseGetResponse', () {
    test('extracts a single OCTET STRING varbind', () {
      final bytes = _buildResponse(varBinds: [
        _VarBind('1.3.6.1.2.1.1.1.0', _Str('EPSON TM-T88V firmware')),
      ]);
      final parsed = parseGetResponse(bytes);
      expect(parsed.varBinds['1.3.6.1.2.1.1.1.0'],
          'EPSON TM-T88V firmware');
    });

    test('extracts multiple varbinds', () {
      final bytes = _buildResponse(varBinds: [
        _VarBind('1.3.6.1.2.1.1.1.0', _Str('Vendor X')),
        _VarBind('1.3.6.1.2.1.1.5.0', _Str('PRINTER01')),
      ]);
      final parsed = parseGetResponse(bytes);
      expect(parsed.varBinds['1.3.6.1.2.1.1.1.0'], 'Vendor X');
      expect(parsed.varBinds['1.3.6.1.2.1.1.5.0'], 'PRINTER01');
    });

    test('skips varbind with noSuchObject (0x80) tag', () {
      final bytes = _buildResponse(varBinds: [
        _VarBind('1.3.6.1.2.1.43.5.1.1.17.1', _NoSuchObject()),
        _VarBind('1.3.6.1.2.1.1.1.0', _Str('OK')),
      ]);
      final parsed = parseGetResponse(bytes);
      expect(parsed.varBinds['1.3.6.1.2.1.1.1.0'], 'OK');
      expect(parsed.varBinds.containsKey('1.3.6.1.2.1.43.5.1.1.17.1'), isFalse);
    });

    test('errorStatus 0 = no error', () {
      final bytes = _buildResponse(varBinds: [
        _VarBind('1.3.6.1.2.1.1.1.0', _Str('x')),
      ]);
      expect(parseGetResponse(bytes).errorStatus, 0);
    });
  });
}

// ---------------- test helpers: build a canned SNMP response ----------------

sealed class _Val {}
class _Str extends _Val { final String s; _Str(this.s); }
class _NoSuchObject extends _Val {}

class _VarBind {
  final String oid;
  final _Val value;
  _VarBind(this.oid, this.value);
}

Uint8List _buildResponse({required List<_VarBind> varBinds}) {
  // Build varbind list
  final vbList = BytesBuilder();
  for (final vb in varBinds) {
    final inner = BytesBuilder();
    final oidBytes = encodeOid(vb.oid);
    inner.add([0x06, oidBytes.length]);
    inner.add(oidBytes);
    switch (vb.value) {
      case _Str s:
        inner.add([0x04, s.s.length]);
        inner.add(s.s.codeUnits);
      case _NoSuchObject _:
        inner.add([0x80, 0x00]);
    }
    final wrapped = _tlv(0x30, inner.toBytes());
    vbList.add(wrapped);
  }
  final vbListTlv = _tlv(0x30, vbList.toBytes());

  // PDU: req-id 1, err-status 0, err-index 0, varbinds
  final pdu = BytesBuilder();
  pdu.add([0x02, 0x01, 0x01]); // request-id = 1
  pdu.add([0x02, 0x01, 0x00]); // error-status = 0
  pdu.add([0x02, 0x01, 0x00]); // error-index = 0
  pdu.add(vbListTlv);
  final pduTlv = _tlv(0xA2, pdu.toBytes()); // GetResponse-PDU

  // Outer message
  final msg = BytesBuilder();
  msg.add([0x02, 0x01, 0x01]); // version = 1 (v2c)
  msg.add([0x04, 0x06]);
  msg.add('public'.codeUnits);
  msg.add(pduTlv);
  return Uint8List.fromList(_tlv(0x30, msg.toBytes()));
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
