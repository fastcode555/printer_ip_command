import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

const List<int> _init = [0x1B, 0x40];
const List<int> _gbkCodepage = [0x1B, 0x74, 0x15];
const List<int> _alignCenter = [0x1B, 0x61, 0x01];
const List<int> _alignLeft = [0x1B, 0x61, 0x00];
const List<int> _boldOn = [0x1B, 0x45, 0x01];
const List<int> _boldOff = [0x1B, 0x45, 0x00];
const List<int> _doubleSizeOn = [0x1D, 0x21, 0x11];
const List<int> _doubleSizeOff = [0x1D, 0x21, 0x00];
const List<int> _fullCut = [0x1D, 0x56, 0x00];
const int _lf = 0x0A;

Uint8List buildReceipt({
  required String title,
  required List<String> lines,
  bool cut = true,
}) {
  final out = BytesBuilder();
  out.add(_init);
  out.add(_gbkCodepage);

  out.add(_alignCenter);
  out.add(_doubleSizeOn);
  out.add(_boldOn);
  out.add(gbk_bytes.encode(title));
  out.addByte(_lf);
  out.add(_boldOff);
  out.add(_doubleSizeOff);

  out.add(_alignLeft);
  for (final line in lines) {
    out.add(gbk_bytes.encode(line));
    out.addByte(_lf);
  }

  out.addByte(_lf);
  out.addByte(_lf);
  out.addByte(_lf);

  if (cut) out.add(_fullCut);
  return out.toBytes();
}
