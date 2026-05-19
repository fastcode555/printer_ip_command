import 'package:printer_ip_command/src/escpos_receipt.dart';
import 'package:test/test.dart';

void main() {
  group('buildReceipt', () {
    test('starts with ESC @ (init) and ESC t 0x15 (GBK codepage)', () {
      final bytes = buildReceipt(title: 'X', lines: const [], cut: false);
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(bytes.sublist(2, 5), [0x1B, 0x74, 0x15]);
    });

    test('ends with GS V 0 (full cut) when cut: true', () {
      final bytes = buildReceipt(title: 'X', lines: const [], cut: true);
      final tail = bytes.sublist(bytes.length - 3);
      expect(tail, [0x1D, 0x56, 0x00]);
    });

    test('does NOT emit cut bytes when cut: false', () {
      final bytes = buildReceipt(title: 'X', lines: const [], cut: false);
      final hasCut = _containsSequence(bytes, [0x1D, 0x56, 0x00]);
      expect(hasCut, isFalse);
    });

    test('encodes Chinese title in GBK (双字节 per char)', () {
      // 测试单 → GBK: 0xB2 0xE2 0xCA 0xD4 0xB5 0xA5 (6 bytes for 3 chars)
      final bytes = buildReceipt(title: '测试单', lines: const [], cut: false);
      expect(_containsSequence(bytes, [0xB2, 0xE2, 0xCA, 0xD4, 0xB5, 0xA5]), isTrue);
    });

    test('emits center alignment (ESC a 1) for title then left (ESC a 0) for body', () {
      final bytes = buildReceipt(title: 'X', lines: const ['line'], cut: false);
      expect(_containsSequence(bytes, [0x1B, 0x61, 0x01]), isTrue); // center
      expect(_containsSequence(bytes, [0x1B, 0x61, 0x00]), isTrue); // left
    });

    test('each body line is terminated by LF', () {
      final bytes = buildReceipt(title: 'X', lines: const ['ab', 'cd'], cut: false);
      // 'ab'\n 'cd'\n  → contains 0x61 0x62 0x0A and 0x63 0x64 0x0A
      expect(_containsSequence(bytes, [0x61, 0x62, 0x0A]), isTrue);
      expect(_containsSequence(bytes, [0x63, 0x64, 0x0A]), isTrue);
    });
  });
}

bool _containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
