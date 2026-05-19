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
