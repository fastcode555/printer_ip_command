import 'package:printer_ip_command/src/escpos_receipt.dart';
import 'package:test/test.dart';

void main() {
  group('buildReceipt — common bytes', () {
    test('starts with ESC @ (init)', () {
      final bytes = buildReceipt(
        title: 'X',
        lines: const [],
        cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    });

    test('ends with GS V 0 (full cut) when cut: true', () {
      final bytes = buildReceipt(
        title: 'X', lines: const [], cut: true,
        encoding: ReceiptEncoding.gbk,
      );
      expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x00]);
    });

    test('does NOT emit cut bytes when cut: false', () {
      final bytes = buildReceipt(
        title: 'X', lines: const [], cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(_containsSequence(bytes, [0x1D, 0x56, 0x00]), isFalse);
    });

    test('emits center alignment then left for title/body', () {
      final bytes = buildReceipt(
        title: 'X', lines: const ['line'], cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(_containsSequence(bytes, [0x1B, 0x61, 0x01]), isTrue);
      expect(_containsSequence(bytes, [0x1B, 0x61, 0x00]), isTrue);
    });

    test('each body line is terminated by LF', () {
      final bytes = buildReceipt(
        title: 'X', lines: const ['ab', 'cd'], cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(_containsSequence(bytes, [0x61, 0x62, 0x0A]), isTrue);
      expect(_containsSequence(bytes, [0x63, 0x64, 0x0A]), isTrue);
    });
  });

  group('buildReceipt — encoding=gbk (mainland)', () {
    test('emits ESC t 0x15 codepage hint', () {
      final bytes = buildReceipt(
        title: 'X', lines: const [], cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(bytes.sublist(2, 5), [0x1B, 0x74, 0x15]);
    });

    test('encodes "测试单" as GBK bytes', () {
      // GBK: 测=B2E2 试=CAD4 单=B5A5
      final bytes = buildReceipt(
        title: '测试单', lines: const [], cut: false,
        encoding: ReceiptEncoding.gbk,
      );
      expect(_containsSequence(bytes,
          [0xB2, 0xE2, 0xCA, 0xD4, 0xB5, 0xA5]), isTrue);
    });
  });

  group('buildReceipt — encoding=big5 (HK / Traditional)', () {
    test('emits FS & to enter Epson Chinese mode (no ESC t 0x15)', () {
      final bytes = buildReceipt(
        title: 'X', lines: const [], cut: false,
        encoding: ReceiptEncoding.big5,
      );
      expect(bytes.sublist(2, 4), [0x1C, 0x26]);
      expect(_containsSequence(bytes, [0x1B, 0x74, 0x15]), isFalse);
    });

    test('encodes "測試單" as Big5 bytes', () {
      // Big5: 測=B4FA 試=B8D5 單=B3E6
      final bytes = buildReceipt(
        title: '測試單', lines: const [], cut: false,
        encoding: ReceiptEncoding.big5,
      );
      expect(_containsSequence(bytes,
          [0xB4, 0xFA, 0xB8, 0xD5, 0xB3, 0xE6]), isTrue);
    });

    test('big5 is the default encoding', () {
      final bytes = buildReceipt(title: 'X', lines: const [], cut: false);
      // FS & marker present, ESC t 0x15 absent → big5 path
      expect(_containsSequence(bytes, [0x1C, 0x26]), isTrue);
      expect(_containsSequence(bytes, [0x1B, 0x74, 0x15]), isFalse);
    });
  });

  group('buildReceipt — encoding=ascii', () {
    test('skips all codepage commands', () {
      final bytes = buildReceipt(
        title: 'X', lines: const [], cut: false,
        encoding: ReceiptEncoding.ascii,
      );
      expect(_containsSequence(bytes, [0x1B, 0x74, 0x15]), isFalse);
      expect(_containsSequence(bytes, [0x1C, 0x26]), isFalse);
    });

    test('drops non-ASCII characters silently', () {
      final bytes = buildReceipt(
        title: 'AB测C', lines: const [], cut: false,
        encoding: ReceiptEncoding.ascii,
      );
      // Should contain A B C but no GBK bytes for 测
      expect(_containsSequence(bytes, [0x41, 0x42, 0x43]), isTrue);
      expect(_containsSequence(bytes, [0xB2, 0xE2]), isFalse);
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
