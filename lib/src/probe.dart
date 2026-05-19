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
  // DLE EOT 1 is the only invasion-free 9100 query: Epson spec defines it as
  // interrupt-class real-time status, never enters the print buffer. Safe even
  // mid-job. We never mix it with other-protocol probes on the same socket —
  // mixing ZPL/TSPL/PJL bytes leaves them in the print buffer of ESC/POS
  // devices and they get printed as garbage characters on paper.
  static const List<int> _escPosStatusQuery = [0x10, 0x04, 0x01];
  // ZPL/TSPL/PJL probes live on their own sockets and are opt-in via [deep].
  static const List<int> _zplHostIdentify = [0x7E, 0x48, 0x49, 0x0D, 0x0A]; // ~HI\r\n

  static Future<ProbeResult> probe(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 2),
    bool deep = false,
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(_escPosStatusQuery);
      // ZPL probe stays in the same connection only in deep mode. The ESC/POS
      // pattern check below short-circuits as soon as a 0x16-like byte arrives,
      // so a real ESC/POS printer would not "buffer" the ~HI bytes — but on
      // slow paths (cross-subnet) the ~HI bytes may still flush ahead of close.
      // Therefore: only send when caller opted into deep / invasive probes.
      if (deep) socket.add(_zplHostIdentify);
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
