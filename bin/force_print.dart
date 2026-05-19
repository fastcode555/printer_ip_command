// Force-print a test slip to an IP that we can't auto-identify as ESC/POS.
// Useful when the device accepts 9100 connections but won't reply to queries.

import 'dart:io';

import 'package:printer_ip_command/printer_ip_command.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('Usage: dart run bin/force_print.dart <ip> [port]');
    exit(64);
  }
  final host = argv[0];
  final port = argv.length > 1 ? int.parse(argv[1]) : 9100;

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
      '它只是不响应状态查询。',
      '',
      'GBK 编码已生效:测试中文。',
    ],
  );

  print('Connecting to $host:$port ...');
  final socket = await Socket.connect(host, port,
      timeout: const Duration(seconds: 3));
  print('Sending ${bytes.length} bytes ...');
  socket.add(bytes);
  await socket.flush();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await socket.close();
  print('Done. Check the printer for output.');
}
