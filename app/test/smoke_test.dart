import 'package:flutter_test/flutter_test.dart';
import 'package:printer_ip_command/printer_ip_command.dart';

void main() {
  test('lib types are importable via path dep', () {
    expect(Protocol.escPos, isA<Protocol>());
    expect(ChannelStatus.success, isA<ChannelStatus>());
    expect(ReceiptEncoding.big5, isA<ReceiptEncoding>());
  });
}
