import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'escpos_status.dart';
import 'protocol.dart';

class ProbeResult {
  final Protocol protocol;
  final Uint8List raw;
  final EscPosStatus? status;

  const ProbeResult({
    required this.protocol,
    required this.raw,
    this.status,
  });

  @override
  String toString() =>
      'ProbeResult(protocol: $protocol, rawBytes: ${raw.length}, status: $status)';
}

class PrinterProbe {
  // ESC/POS real-time status query — every ESC/POS printer must respond.
  static const List<int> _escPosStatusQuery = [0x10, 0x04, 0x01];
  // ZPL host identification — Zebra replies with model banner.
  static const List<int> _zplHostIdentify = [0x7E, 0x48, 0x49, 0x0D, 0x0A]; // ~HI\r\n

  static Future<ProbeResult> probe(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(_escPosStatusQuery);
      socket.add(_zplHostIdentify);
      await socket.flush();

      final received = BytesBuilder();
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;

      sub = socket.listen(
        (data) {
          received.add(data);
          // First byte that matches ESC/POS pattern → we have enough.
          if (received.length == 1 && (received.toBytes()[0] & 0x93) == 0x12) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      try {
        await completer.future.timeout(timeout);
      } on TimeoutException {
        // partial or no response — fall through to whatever we have
      } finally {
        await sub.cancel();
      }

      final raw = received.toBytes();
      final protocol = detectProtocol(raw);
      EscPosStatus? status;
      if (protocol == Protocol.escPos) {
        status = parseStatusByte(raw[0]);
      }
      return ProbeResult(protocol: protocol, raw: raw, status: status);
    } finally {
      socket.destroy();
    }
  }
}
