import 'package:printer_ip_command/src/escpos_status.dart';
import 'package:test/test.dart';

void main() {
  group('parseStatusByte (DLE EOT 1)', () {
    test('idle online status: bit3=0, bit5=0, bit6=0', () {
      // 0b00010110 = 0x16: fixed bits set, drawer-pin high, online, cover closed
      final status = parseStatusByte(0x16);
      expect(status.online, isTrue);
      expect(status.coverOpen, isFalse);
      expect(status.paperFeedButtonPressed, isFalse);
    });

    test('offline when bit3 is set', () {
      // 0b00011110 = 0x1E: bit3=1 → offline
      final status = parseStatusByte(0x1E);
      expect(status.online, isFalse);
    });

    test('cover open when bit5 is set', () {
      // 0b00110110 = 0x36: bit5=1 → cover open
      final status = parseStatusByte(0x36);
      expect(status.coverOpen, isTrue);
      expect(status.online, isTrue);
    });

    test('paper feed button pressed when bit6 is set', () {
      // 0b01010110 = 0x56: bit6=1 → feed button pressed
      final status = parseStatusByte(0x56);
      expect(status.paperFeedButtonPressed, isTrue);
    });

    test('rejects bytes missing the fixed bit-pattern (bit0=1, bit1=0, bit4=1, bit7=0)', () {
      // 0x00 is not a valid ESC/POS DLE EOT response
      expect(() => parseStatusByte(0x00), throwsFormatException);
      // 0xFF is not valid either (bit7 must be 0)
      expect(() => parseStatusByte(0xFF), throwsFormatException);
    });
  });
}
