import 'dart:typed_data';

import 'package:enough_convert/big5.dart';
import 'package:gbk_codec/gbk_codec.dart';

/// Receipt text encoding.
///
/// The printer's Chinese ROM (Simplified vs Traditional) is fixed at
/// manufacture — sending Big5 bytes to a Simplified-ROM unit will produce
/// random glyphs. Pick the encoding that matches the target market's printers.
enum ReceiptEncoding {
  /// PC437 / pure ASCII. Works on every printer but no Chinese characters.
  ascii,

  /// Simplified Chinese (mainland market, e.g. mainland Epson, Xprinter,
  /// 佳博). Uses `ESC t 0x15` to hint the codepage, then GBK-encoded bytes.
  gbk,

  /// Traditional Chinese (HK / TW market). Uses `FS &` to enter Epson Chinese
  /// mode, then Big5-encoded bytes. The printer's Big5 ROM does the glyph
  /// lookup.
  big5,
}

const List<int> _init = [0x1B, 0x40];
const List<int> _alignCenter = [0x1B, 0x61, 0x01];
const List<int> _alignLeft = [0x1B, 0x61, 0x00];
const List<int> _boldOn = [0x1B, 0x45, 0x01];
const List<int> _boldOff = [0x1B, 0x45, 0x00];
const List<int> _doubleSizeOn = [0x1D, 0x21, 0x11];
const List<int> _doubleSizeOff = [0x1D, 0x21, 0x00];
const List<int> _fullCut = [0x1D, 0x56, 0x00];
const List<int> _gbkCodepageHint = [0x1B, 0x74, 0x15]; // ESC t 0x15
const List<int> _enterChineseMode = [0x1C, 0x26]; // FS &
const int _lf = 0x0A;

Uint8List buildReceipt({
  required String title,
  required List<String> lines,
  ReceiptEncoding encoding = ReceiptEncoding.big5,
  bool cut = true,
}) {
  final out = BytesBuilder();
  out.add(_init);
  switch (encoding) {
    case ReceiptEncoding.ascii:
      break;
    case ReceiptEncoding.gbk:
      out.add(_gbkCodepageHint);
      break;
    case ReceiptEncoding.big5:
      out.add(_enterChineseMode);
      break;
  }

  List<int> enc(String s) => _encode(s, encoding);

  out.add(_alignCenter);
  out.add(_doubleSizeOn);
  out.add(_boldOn);
  out.add(enc(title));
  out.addByte(_lf);
  out.add(_boldOff);
  out.add(_doubleSizeOff);

  out.add(_alignLeft);
  for (final line in lines) {
    out.add(enc(line));
    out.addByte(_lf);
  }

  out.addByte(_lf);
  out.addByte(_lf);
  out.addByte(_lf);

  if (cut) out.add(_fullCut);
  return out.toBytes();
}

List<int> _encode(String s, ReceiptEncoding encoding) {
  switch (encoding) {
    case ReceiptEncoding.ascii:
      // Drop any non-ASCII; CP437 fallback would be more thorough.
      return s.codeUnits.where((c) => c >= 0x20 && c <= 0x7E || c == 0x0A).toList();
    case ReceiptEncoding.gbk:
      return gbk_bytes.encode(s);
    case ReceiptEncoding.big5:
      return const Big5Codec(allowInvalid: true).encode(s);
  }
}
