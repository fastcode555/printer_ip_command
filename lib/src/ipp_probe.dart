import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class IppResult {
  final int statusCode;
  final String? makeAndModel;
  final int? state;
  final List<String> documentFormats;

  const IppResult({
    required this.statusCode,
    this.makeAndModel,
    this.state,
    this.documentFormats = const [],
  });

  @override
  String toString() =>
      'IppResult(makeAndModel: $makeAndModel, state: $state, '
      'formats: $documentFormats, statusCode: 0x${statusCode.toRadixString(16)})';
}

// IPP value tags we care about.
const int _tagInteger = 0x21;
const int _tagEnum = 0x23;
const int _tagTextWithoutLang = 0x41;
const int _tagNameWithoutLang = 0x42;
const int _tagKeyword = 0x44;
const int _tagUri = 0x45;
const int _tagCharset = 0x47;
const int _tagNaturalLang = 0x48;
const int _tagMimeMedia = 0x49;
const int _tagEndOfAttributes = 0x03;

Uint8List buildIppGetPrinterAttributesRequest({
  required String printerUri,
  int requestId = 1,
}) {
  final b = BytesBuilder();
  b.add([0x01, 0x01]); // version 1.1
  b.add([0x00, 0x0B]); // operation: Get-Printer-Attributes
  b.add(_u32(requestId));

  b.addByte(0x01); // operation-attributes-tag
  _writeAttr(b, _tagCharset, 'attributes-charset', 'utf-8');
  _writeAttr(b, _tagNaturalLang, 'attributes-natural-language', 'en');
  _writeAttr(b, _tagUri, 'printer-uri', printerUri);

  b.addByte(_tagEndOfAttributes);
  return b.toBytes();
}

IppResult parseIppResponse(Uint8List bytes) {
  final r = _Reader(bytes);
  r.skip(2); // version
  final statusCode = r.u16();
  r.skip(4); // request-id

  String? makeAndModel;
  int? state;
  final formats = <String>[];

  String? lastName;
  String? currentGroupAttrName;

  while (!r.eof) {
    final tag = r.u8();
    if (tag == _tagEndOfAttributes) break;
    if (tag <= 0x0F) {
      // group-delimiter tag (operation/printer/job/...). just continue.
      lastName = null;
      continue;
    }
    final nameLen = r.u16();
    final name = nameLen > 0 ? String.fromCharCodes(r.bytes(nameLen)) : '';
    final valueLen = r.u16();
    final valueBytes = r.bytes(valueLen);

    final attrName = name.isEmpty ? lastName : name;
    if (name.isNotEmpty) lastName = name;
    currentGroupAttrName = attrName;
    if (attrName == null) continue;

    switch (tag) {
      case _tagTextWithoutLang:
      case _tagNameWithoutLang:
        if (attrName == 'printer-make-and-model') {
          makeAndModel = String.fromCharCodes(valueBytes);
        }
        break;
      case _tagEnum:
      case _tagInteger:
        if (attrName == 'printer-state' && valueBytes.length == 4) {
          state = (valueBytes[0] << 24) |
              (valueBytes[1] << 16) |
              (valueBytes[2] << 8) |
              valueBytes[3];
        }
        break;
      case _tagMimeMedia:
      case _tagKeyword:
        if (attrName == 'document-format-supported') {
          formats.add(String.fromCharCodes(valueBytes));
        }
        break;
    }
    // touch currentGroupAttrName to suppress unused-local warning under lints
    assert(currentGroupAttrName == attrName);
  }

  return IppResult(
    statusCode: statusCode,
    makeAndModel: makeAndModel,
    state: state,
    documentFormats: List.unmodifiable(formats),
  );
}

class IppProbe {
  static Future<IppResult?> query(
    String host, {
    int port = 631,
    String path = '/ipp/print',
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final printerUri = 'ipp://$host:$port$path';
    final body = buildIppGetPrinterAttributesRequest(printerUri: printerUri);

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('http://$host:$port$path'))
          .timeout(timeout);
      req.headers.contentType = ContentType('application', 'ipp');
      req.headers.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final out = BytesBuilder();
      await for (final chunk in resp.timeout(timeout)) {
        out.add(chunk);
      }
      return parseIppResponse(out.toBytes());
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on HttpException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

// ---- helpers ----

void _writeAttr(BytesBuilder b, int tag, String name, String value) {
  b.addByte(tag);
  b.add(_u16(name.length));
  b.add(name.codeUnits);
  b.add(_u16(value.length));
  b.add(value.codeUnits);
}

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

class _Reader {
  final Uint8List _bytes;
  int _pos = 0;
  _Reader(this._bytes);

  bool get eof => _pos >= _bytes.length;

  int u8() => _bytes[_pos++];
  int u16() {
    final v = (_bytes[_pos] << 8) | _bytes[_pos + 1];
    _pos += 2;
    return v;
  }

  Uint8List bytes(int n) {
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return out;
  }

  void skip(int n) => _pos += n;
}
