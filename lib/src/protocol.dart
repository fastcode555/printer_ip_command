import 'dart:typed_data';

enum Protocol { escPos, star, zpl, tspl, unknown }

Protocol detectProtocol(Uint8List bytes) {
  if (bytes.isEmpty) return Protocol.unknown;

  if (bytes.length == 1 && (bytes[0] & 0x93) == 0x12) {
    return Protocol.escPos;
  }

  final asAscii = String.fromCharCodes(bytes);
  if (asAscii.contains('ZEBRA')) return Protocol.zpl;

  if (_looksLikePrintableModelString(bytes)) return Protocol.tspl;

  return Protocol.unknown;
}

bool _looksLikePrintableModelString(Uint8List bytes) {
  var hasLetter = false;
  for (final b in bytes) {
    final isPrintable = b >= 0x20 && b <= 0x7E;
    final isWs = b == 0x0A || b == 0x0D || b == 0x09;
    if (!isPrintable && !isWs) return false;
    if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)) hasLetter = true;
  }
  return hasLetter;
}
