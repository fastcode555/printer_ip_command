import 'dart:typed_data';

const int _tagInteger = 0x02;
const int _tagOctetString = 0x04;
const int _tagNull = 0x05;
const int _tagOid = 0x06;
const int _tagSequence = 0x30;
const int _tagGetRequest = 0xA0;
const int _tagGetResponse = 0xA2;
const int _tagNoSuchObject = 0x80;
const int _tagNoSuchInstance = 0x81;
const int _tagEndOfMibView = 0x82;

class SnmpResponse {
  final int requestId;
  final int errorStatus;
  final int errorIndex;
  final Map<String, String> varBinds;

  const SnmpResponse({
    required this.requestId,
    required this.errorStatus,
    required this.errorIndex,
    required this.varBinds,
  });
}

Uint8List encodeOid(String oid) {
  final parts = oid.split('.').map(int.parse).toList();
  if (parts.length < 2) throw FormatException('OID needs ≥2 arcs: $oid');
  final out = <int>[40 * parts[0] + parts[1]];
  for (var i = 2; i < parts.length; i++) {
    out.addAll(_base128(parts[i]));
  }
  return Uint8List.fromList(out);
}

String decodeOid(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final first = bytes[0];
  final parts = <int>[first ~/ 40, first % 40];
  var i = 1;
  while (i < bytes.length) {
    var v = 0;
    while (i < bytes.length && (bytes[i] & 0x80) != 0) {
      v = (v << 7) | (bytes[i] & 0x7F);
      i++;
    }
    if (i >= bytes.length) break;
    v = (v << 7) | bytes[i];
    parts.add(v);
    i++;
  }
  return parts.join('.');
}

List<int> _base128(int v) {
  if (v == 0) return [0];
  final stack = <int>[];
  while (v > 0) {
    stack.add(v & 0x7F);
    v >>= 7;
  }
  final out = <int>[];
  for (var i = stack.length - 1; i >= 0; i--) {
    out.add(stack[i] | (i == 0 ? 0 : 0x80));
  }
  return out;
}

Uint8List buildGetRequest({
  required String community,
  required int requestId,
  required List<String> oids,
}) {
  final varBindList = BytesBuilder();
  for (final oid in oids) {
    final oidBytes = encodeOid(oid);
    final inner = BytesBuilder();
    inner.add(_tlv(_tagOid, oidBytes));
    inner.add(_tlv(_tagNull, const []));
    varBindList.add(_tlv(_tagSequence, inner.toBytes()));
  }
  final vbListTlv = _tlv(_tagSequence, varBindList.toBytes());

  final pdu = BytesBuilder();
  pdu.add(_tlvInt(_tagInteger, requestId));
  pdu.add(_tlvInt(_tagInteger, 0)); // error-status
  pdu.add(_tlvInt(_tagInteger, 0)); // error-index
  pdu.add(vbListTlv);
  final pduTlv = _tlv(_tagGetRequest, pdu.toBytes());

  final msg = BytesBuilder();
  msg.add(_tlvInt(_tagInteger, 1)); // version = 1 (SNMPv2c)
  msg.add(_tlv(_tagOctetString, community.codeUnits));
  msg.add(pduTlv);
  return Uint8List.fromList(_tlv(_tagSequence, msg.toBytes()));
}

SnmpResponse parseGetResponse(Uint8List bytes) {
  final r = _Reader(bytes);
  _expect(r.u8(), _tagSequence);
  r.length(); // outer length

  _expect(r.u8(), _tagInteger);
  r.read(r.length()); // version

  _expect(r.u8(), _tagOctetString);
  r.read(r.length()); // community

  _expect(r.u8(), _tagGetResponse);
  r.length();

  _expect(r.u8(), _tagInteger);
  final requestId = _readInt(r);
  _expect(r.u8(), _tagInteger);
  final errorStatus = _readInt(r);
  _expect(r.u8(), _tagInteger);
  final errorIndex = _readInt(r);

  _expect(r.u8(), _tagSequence);
  final vbListLen = r.length();
  final vbListEnd = r.pos + vbListLen;
  final varBinds = <String, String>{};
  while (r.pos < vbListEnd) {
    _expect(r.u8(), _tagSequence);
    final vbLen = r.length();
    final vbEnd = r.pos + vbLen;
    _expect(r.u8(), _tagOid);
    final oidBytes = r.read(r.length());
    final oid = decodeOid(oidBytes);
    final valueTag = r.u8();
    final valueLen = r.length();
    final valueBytes = r.read(valueLen);
    switch (valueTag) {
      case _tagOctetString:
        varBinds[oid] = String.fromCharCodes(valueBytes);
        break;
      case _tagInteger:
        varBinds[oid] = _bytesToInt(valueBytes).toString();
        break;
      case _tagNoSuchObject:
      case _tagNoSuchInstance:
      case _tagEndOfMibView:
        // silently skip
        break;
      default:
        // unknown tag — keep raw hex for diagnostics
        varBinds[oid] = valueBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join('');
    }
    r.pos = vbEnd;
  }

  return SnmpResponse(
    requestId: requestId,
    errorStatus: errorStatus,
    errorIndex: errorIndex,
    varBinds: Map.unmodifiable(varBinds),
  );
}

// ---- helpers ----

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

List<int> _tlvInt(int tag, int value) {
  final body = _encodeInt(value);
  return _tlv(tag, body);
}

List<int> _encodeInt(int value) {
  if (value == 0) return [0];
  final bytes = <int>[];
  var v = value;
  final negative = v < 0;
  // We only handle non-negative request-ids in our use case;
  // simple two's complement style for both is overkill here.
  if (negative) {
    // Not needed for our SNMP request building; reject early.
    throw ArgumentError('negative int not supported');
  }
  while (v > 0) {
    bytes.insert(0, v & 0xFF);
    v >>= 8;
  }
  // High-bit must be 0 for positive; prepend 0x00 if set.
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0x00);
  return bytes;
}

int _bytesToInt(Uint8List b) {
  if (b.isEmpty) return 0;
  var v = 0;
  for (final x in b) {
    v = (v << 8) | x;
  }
  return v;
}

int _readInt(_Reader r) {
  final n = r.length();
  final bytes = r.read(n);
  return _bytesToInt(bytes);
}

void _expect(int actual, int expected) {
  if (actual != expected) {
    throw FormatException(
      'SNMP parse: expected tag 0x${expected.toRadixString(16)}, '
      'got 0x${actual.toRadixString(16)}',
    );
  }
}

class _Reader {
  final Uint8List _buf;
  int pos = 0;
  _Reader(this._buf);

  int u8() => _buf[pos++];

  int length() {
    final first = u8();
    if ((first & 0x80) == 0) return first;
    final n = first & 0x7F;
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | u8();
    }
    return v;
  }

  Uint8List read(int n) {
    final out = Uint8List.sublistView(_buf, pos, pos + n);
    pos += n;
    return out;
  }
}
