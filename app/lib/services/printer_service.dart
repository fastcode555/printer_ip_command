import 'dart:async';
import 'dart:io';

import 'package:printer_ip_command/printer_ip_command.dart';

class PrintTestException implements Exception {
  final String message;
  PrintTestException(this.message);
  @override
  String toString() => 'PrintTestException: $message';
}

class PrinterService {
  Future<IdentifyReport> identify(String host, {bool deep = false}) {
    return PrinterIdentifier.identify(host, deep: deep);
  }

  /// Returns the number of bytes written.
  Future<int> printTest(
    String host,
    ReceiptEncoding encoding, {
    int port = 9100,
    Duration connectTimeout = const Duration(seconds: 3),
  }) async {
    final bytes = buildReceipt(
      title: '识别探测',
      lines: [
        '--------------------------------',
        'IP    : $host',
        'Port  : $port',
        'Time  : ${DateTime.now().toIso8601String()}',
        '--------------------------------',
        '如果你看到这张纸,这台机',
        '是 ESC/POS 兼容的热敏打印机。',
        '编码: ${encoding.name}',
      ],
      encoding: encoding,
    );

    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException catch (e) {
      throw PrintTestException('connect failed: ${e.message}');
    } on TimeoutException {
      throw PrintTestException('connect timeout after ${connectTimeout.inSeconds}s');
    }

    try {
      socket.add(bytes);
      await socket.flush();
      // Some thermals need a brief pause before the FIN; without it the cut
      // command can arrive at the printer before the spool buffer drains.
      // Mirrors bin/force_print.dart.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } finally {
      await socket.close();
    }
    return bytes.length;
  }
}
