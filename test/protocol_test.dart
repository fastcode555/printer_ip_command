import 'dart:typed_data';

import 'package:printer_ip_command/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('detectProtocol', () {
    test('single byte matching ESC/POS DLE EOT 1 pattern → escPos', () {
      expect(detectProtocol(Uint8List.fromList([0x16])), Protocol.escPos);
    });

    test('ZPL ~HI response containing "ZEBRA" → zpl', () {
      final bytes = Uint8List.fromList(
        'ZEBRA TECHNOLOGIES,ZTC GK420d,V53.17.16Z\r\n'.codeUnits,
      );
      expect(detectProtocol(bytes), Protocol.zpl);
    });

    test('TSPL ~!T response: ASCII model string starting with letters → tspl', () {
      final bytes = Uint8List.fromList('TTP-244 Plus\r\n'.codeUnits);
      expect(detectProtocol(bytes), Protocol.tspl);
    });

    test('empty response → unknown', () {
      expect(detectProtocol(Uint8List(0)), Protocol.unknown);
    });

    test('garbage byte that fails all signatures → unknown', () {
      expect(detectProtocol(Uint8List.fromList([0xFF])), Protocol.unknown);
    });
  });
}
