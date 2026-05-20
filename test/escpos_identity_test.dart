import 'dart:typed_data';

import 'package:printer_ip_command/src/escpos_identity.dart';
import 'package:test/test.dart';

void main() {
  group('parseGsIResponse', () {
    test('Type A: NUL-terminated ASCII (no header)', () {
      // 'Xprinter\0' = 9 bytes
      final bytes = Uint8List.fromList([0x58, 0x70, 0x72, 0x69, 0x6E, 0x74, 0x65, 0x72, 0x00]);
      expect(parseGsIResponse(bytes), 'Xprinter');
    });

    test('Type B: 0x5F header + ASCII + NUL', () {
      // 0x5F 'TM-T88V' 0x00
      final bytes = Uint8List.fromList([0x5F, 0x54, 0x4D, 0x2D, 0x54, 0x38, 0x38, 0x56, 0x00]);
      expect(parseGsIResponse(bytes), 'TM-T88V');
    });

    test('GS I 0x45 sample: header + CHINA GB18030 + NUL', () {
      // Real bytes captured from TM-T88III 8.00 ESC/POS firmware via
      // `printf '\x1D\x49\x45' | nc 192.168.225.78 9100`:
      //   5f 43 48 49 4e 41 20 47 42 31 38 30 33 30 00
      // After parseGsIResponse strips the 0x5F header, expect 'CHINA GB18030'.
      final bytes = Uint8List.fromList([
        0x5F, 0x43, 0x48, 0x49, 0x4E, 0x41, 0x20,
        0x47, 0x42, 0x31, 0x38, 0x30, 0x33, 0x30, 0x00,
      ]);
      expect(parseGsIResponse(bytes), 'CHINA GB18030');
    });

    test('returns null when bytes are empty', () {
      expect(parseGsIResponse(Uint8List(0)), isNull);
    });

    test('returns null when only NUL', () {
      expect(parseGsIResponse(Uint8List.fromList([0x00])), isNull);
    });

    test('strips trailing NUL even without explicit terminator inside buffer', () {
      // Some printers send data without trailing NUL — accept that too.
      final bytes = Uint8List.fromList('EPSON'.codeUnits);
      expect(parseGsIResponse(bytes), 'EPSON');
    });

    test('rejects non-printable garbage as null', () {
      final bytes = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(parseGsIResponse(bytes), isNull);
    });
  });
}
